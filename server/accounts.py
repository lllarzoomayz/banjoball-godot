"""Private, loopback-only account store. Gameplay server owns match results.

No passwords/tokens in logs. Registration deadline checked on every request.
The service key and sqlite database belong in the server data volume, never APK.
"""
import datetime as dt
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
import unicodedata
from collections import defaultdict, deque
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

UTC = dt.timezone.utc


class Rejected(ValueError):
    pass


class Store:
    def __init__(self, data, config, now=time.time):
        self.data, self.config, self.now = Path(data), Path(config), now
        self.data.mkdir(parents=True, exist_ok=True)
        self.path = self.data / 'accounts.sqlite3'
        self.hash_slots = threading.BoundedSemaphore(2)
        self.limits = defaultdict(deque)
        self.lock = threading.Lock()
        with self.db() as db:
            db.executescript('''
              PRAGMA journal_mode=WAL;
              CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL,
                nickname TEXT NOT NULL, nick_key TEXT UNIQUE NOT NULL,
                salt BLOB NOT NULL, password BLOB NOT NULL, created REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS sessions (
                digest TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS matches (
                id TEXT PRIMARY KEY, result TEXT NOT NULL, finished REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS participation (
                match_id TEXT NOT NULL, user_id TEXT NOT NULL, outcome TEXT NOT NULL,
                PRIMARY KEY(match_id,user_id));
            ''')

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def settings(self):
        return json.loads(self.config.read_text(encoding='utf-8'))

    def registration_open(self):
        cfg = self.settings()
        deadline = dt.datetime.fromisoformat(cfg['registration_closes_at'])
        if deadline.tzinfo is None:
            raise Rejected('Invalid server deadline')
        return cfg.get('registration_enabled', False) and self.now() < deadline.timestamp()

    def throttle(self, key, limit=10, period=60):
        with self.lock:
            stamp = self.now()
            if len(self.limits) > 4096:
                self.limits = defaultdict(deque, {k:v for k,v in self.limits.items() if v and v[-1] > stamp-period})
            queue = self.limits[key]
            while queue and queue[0] <= stamp-period:
                queue.popleft()
            if len(queue) >= limit:
                raise Rejected('操作太频繁，请稍后再试 / Too many attempts')
            queue.append(stamp)

    @staticmethod
    def nickname(value):
        value = unicodedata.normalize('NFKC', str(value)).strip()
        if not 2 <= len(value) <= 20 or any(unicodedata.category(c).startswith('C') for c in value):
            raise Rejected('昵称需要 2–20 个可见字符 / Nickname: 2–20 visible characters')
        return value, value.casefold()

    @staticmethod
    def username(value):
        value = str(value).strip().lower()
        if not re.fullmatch(r'[a-z0-9_]{3,24}', value):
            raise Rejected('账号需要 3–24 位字母、数字或下划线 / Username: 3–24 ASCII letters, digits, _')
        return value

    def password_hash(self, password, salt):
        if not isinstance(password, str) or not 8 <= len(password) <= 128:
            raise Rejected('密码需要 8–128 个字符 / Password: 8–128 characters')
        if not self.hash_slots.acquire(blocking=False):
            raise Rejected('登录服务繁忙，请稍后再试 / Login busy')
        try:
            return hashlib.scrypt(password.encode(), salt=salt, n=32768, r=8, p=3, maxmem=128*1024*1024, dklen=32)
        finally:
            self.hash_slots.release()

    def profile(self, uid):
        with self.db() as db:
            row = db.execute('SELECT id,username,nickname FROM users WHERE id=?', (uid,)).fetchone()
            if not row:
                raise Rejected('账号不存在 / Account not found')
            counts = dict(db.execute('SELECT outcome,count(*) FROM participation WHERE user_id=? GROUP BY outcome', (uid,)))
        return dict(row) | {'completed':sum(counts.get(k,0) for k in ('win','loss','draw')),
                            'wins':counts.get('win',0), 'losses':counts.get('loss',0), 'draws':counts.get('draw',0)}

    def session(self, uid):
        token = secrets.token_urlsafe(32)
        with self.db() as db:
            db.execute('DELETE FROM sessions WHERE expires<=?', (self.now(),))
            db.execute('INSERT INTO sessions VALUES (?,?,?)', (hashlib.sha256(token.encode()).hexdigest(), uid,
                       self.now()+int(self.settings().get('session_days',30))*86400))
        return {'token':token, 'profile':self.profile(uid)}

    def authenticate(self, token):
        with self.db() as db:
            row = db.execute('SELECT user_id FROM sessions WHERE digest=? AND expires>?',
                             (hashlib.sha256(str(token).encode()).hexdigest(), self.now())).fetchone()
        if not row:
            raise Rejected('登录已过期，请重新登录 / Sign in again')
        return row[0]

    def dispatch(self, action, body):
        if action in ('register','login'):
            self.throttle('ip:'+str(body.get('remote','unknown')))
            name = self.username(body.get('username',''))
            self.throttle('name:'+name)
        if action == 'register':
            if not self.registration_open():
                raise Rejected('注册已关闭，已有账号仍可登录 / Registration closed; existing accounts can sign in')
            nick, key = self.nickname(body.get('nickname',''))
            salt = secrets.token_bytes(16)
            digest = self.password_hash(body.get('password'),salt)
            uid = secrets.token_hex(16)
            try:
                with self.db() as db:
                    # Recheck after expensive hashing, including at the cutoff boundary.
                    if not self.registration_open():
                        raise Rejected('注册已关闭 / Registration closed')
                    db.execute('INSERT INTO users VALUES (?,?,?,?,?,?,?)', (uid,name,nick,key,salt,digest,self.now()))
            except sqlite3.IntegrityError:
                raise Rejected('账号或昵称已被使用 / Username or nickname already taken') from None
            return self.session(uid)
        if action == 'login':
            with self.db() as db:
                row = db.execute('SELECT * FROM users WHERE username=?',(name,)).fetchone()
            digest = self.password_hash(body.get('password'), row['salt'] if row else b'nonexistent-user')
            if not row or not hmac.compare_digest(digest,row['password']):
                raise Rejected('账号或密码错误 / Incorrect username or password')
            return self.session(row['id'])
        if action == 'resume':
            return {'token':body['token'], 'profile':self.profile(self.authenticate(body['token']))}
        if action == 'profile':
            return {'profile':self.profile(body['id'])}
        if action == 'logout':
            with self.db() as db:
                db.execute('DELETE FROM sessions WHERE digest=?',(hashlib.sha256(str(body.get('token','')).encode()).hexdigest(),))
            return {'signed_out':True}
        if action == 'rename':
            uid = self.authenticate(body.get('token',''))
            self.throttle('rename:'+uid, 3)
            nick, key = self.nickname(body.get('nickname',''))
            try:
                with self.db() as db:
                    db.execute('UPDATE users SET nickname=?,nick_key=? WHERE id=?',(nick,key,uid))
            except sqlite3.IntegrityError:
                raise Rejected('昵称已被使用 / Nickname already taken') from None
            return {'profile':self.profile(uid)}
        if action == 'settle':
            match_id = body.get('match_id','')
            entries = body.get('players',[])
            if not re.fullmatch(r'[a-f0-9]{32}',match_id) or not 1 <= len(entries) <= 12:
                raise Rejected('Invalid match')
            seen = set()
            for p in entries:
                if p.get('outcome') not in ('win','loss','draw','abandoned') or p.get('id') in seen:
                    raise Rejected('Invalid result')
                self.profile(p['id']);seen.add(p['id'])
            result = json.dumps(sorted(entries,key=lambda p:p['id']),sort_keys=True)
            with self.db() as db:
                previous = db.execute('SELECT result FROM matches WHERE id=?',(match_id,)).fetchone()
                if previous:
                    if previous[0] != result:
                        raise Rejected('Conflicting duplicate result')
                    return {'saved':True,'duplicate':True}
                db.execute('INSERT INTO matches VALUES (?,?,?)',(match_id,result,self.now()))
                db.executemany('INSERT INTO participation VALUES (?,?,?)',[(match_id,p['id'],p['outcome']) for p in entries])
            return {'saved':True,'duplicate':False}
        if action == 'status':
            return {'registration_open':self.registration_open(), 'registration_closes_at':self.settings()['registration_closes_at']}
        raise Rejected('Unknown action')


def serve():
    root = Path(os.environ.get('BANJO_DATA',Path(__file__).parent/'data'))
    config = Path(os.environ.get('BANJO_CONFIG',Path(__file__).parent/'config.json'))
    store = Store(root,config)
    key_path = root/'service.key'
    if not key_path.exists():
        key_path.write_text(secrets.token_urlsafe(48),encoding='ascii')
    service_key = key_path.read_text(encoding='ascii').strip()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):
            pass

        def do_POST(self):
            if not hmac.compare_digest(self.headers.get('Authorization',''), 'Bearer '+service_key):
                self.send_error(403);return
            try:
                length=int(self.headers.get('Content-Length','0'))
                if not 0 < length <= 16384:
                    raise Rejected('Invalid request size')
                body=json.loads(self.rfile.read(length))
                result={'ok':True, **store.dispatch(self.path.lstrip('/'),body)}
            except (Rejected,ValueError,KeyError,TypeError) as exc:
                result={'ok':False,'error':str(exc)}
            except Exception:
                result={'ok':False,'error':'账号服务暂不可用 / Account service unavailable'}
            payload=json.dumps(result,ensure_ascii=False).encode()
            self.send_response(200);self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)

    print('Account service listening on loopback:27890',flush=True)
    ThreadingHTTPServer(('127.0.0.1',27890),Handler).serve_forever()


if __name__ == '__main__':
    serve()
