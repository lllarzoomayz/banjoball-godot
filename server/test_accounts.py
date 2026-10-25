import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path
from accounts import Store, Rejected


class AccountTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.cfg=self.root/'config.json'
        self.cfg.write_text(json.dumps({'registration_enabled':True,'registration_closes_at':'2026-11-01T00:00:00+08:00'}))
        self.cutoff=dt.datetime.fromisoformat('2026-10-31T16:00:00+00:00').timestamp()
        self.now=self.cutoff-10
        self.store=Store(self.root,self.cfg,lambda:self.now)

    def register(self, user='player', nick='球员一'):
        return self.store.dispatch('register',dict(username=user,nickname=nick,password='test-password',remote=user))

    def test_cutoff_login_and_reopen(self):
        session=self.register();self.now=self.cutoff
        with self.assertRaises(Rejected):self.register('another','球员二')
        logged=self.store.dispatch('login',dict(username='PLAYER',password='test-password',remote='x'))
        self.assertEqual(logged['profile']['id'],session['profile']['id'])
        self.assertEqual(self.store.authenticate(logged['token']),session['profile']['id'])
        cfg=json.loads(self.cfg.read_text());cfg['registration_closes_at']='2026-12-01T00:00:00+08:00'
        self.cfg.write_text(json.dumps(cfg));self.register('another','球员二')

    def test_normalization_and_password(self):
        self.register(nick='Ａlice')
        with self.assertRaises(Rejected):self.register('another','alice')
        with self.assertRaises(Rejected):self.store.dispatch('login',dict(username='player',password='wrong-password'))
        with self.store.db() as db:
            row=db.execute('SELECT password,salt FROM users').fetchone()
            self.assertEqual(len(row['password']),32);self.assertEqual(len(row['salt']),16)
            self.assertNotEqual(row['password'],b'test-password')

    def test_stats_idempotence_and_no_winrate(self):
        a=self.register();b=self.register('player2','球员二')
        result={'match_id':'a'*32,'players':[{'id':a['profile']['id'],'outcome':'win'}, {'id':b['profile']['id'],'outcome':'loss'}]}
        self.store.dispatch('settle',result);self.store.dispatch('settle',result)
        p=self.store.profile(a['profile']['id']);self.assertEqual((p['completed'],p['wins']),(1,1));self.assertNotIn('win_rate',p)
        result['players'][0]['outcome']='loss'
        with self.assertRaises(Rejected):self.store.dispatch('settle',result)
        self.store.dispatch('settle',{'match_id':'b'*32,'players':[{'id':a['profile']['id'],'outcome':'abandoned'}]})
        self.assertEqual(self.store.profile(a['profile']['id'])['completed'],1)

    def test_session_expiry_and_rename(self):
        a=self.register();b=self.register('player2','球员二')
        with self.assertRaises(Rejected):self.store.dispatch('rename',{'token':a['token'],'nickname':'球员二'})
        self.store.dispatch('rename',{'token':a['token'],'nickname':'新名字'})
        self.assertEqual(self.store.dispatch('resume',{'token':a['token']})['profile']['nickname'],'新名字')
        self.now+=31*86400
        with self.assertRaises(Rejected):self.store.authenticate(a['token'])

    def test_logout_revokes_only_selected_session(self):
        a=self.register();b=self.store.dispatch('login',dict(username='player',password='test-password'))
        self.store.dispatch('logout',{'token':a['token']})
        with self.assertRaises(Rejected):self.store.authenticate(a['token'])
        self.assertEqual(self.store.authenticate(b['token']),a['profile']['id'])


if __name__=='__main__':unittest.main()
