"""Check the Git index, or publication files before Git initialization.

This is a focused release check, not a guarantee of absence of every secret.
Only filenames/reasons are printed; matched secret values are never printed.
"""
from pathlib import Path
import re, subprocess, sys
root=Path(__file__).resolve().parents[1]
if (root/'.git').exists():
    names=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
    paths=[root/n for n in names if n]
else:
    paths=[p for p in root.rglob('*') if p.is_file() and not any(x in p.parts for x in ('.godot','.local','__pycache__','node_modules'))]
errors=[]
blocked_suffixes={'.key','.pem','.keystore','.jks','.p12','.pfx','.apk','.aab','.zip','.gz','.sqlite3','.db'}
patterns=[('private key',rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,}-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
          ('GitHub token',rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b'),
          ('cloud credential',rb'\b(?:AKIA[0-9A-Z]{16}|AKID[A-Za-z0-9]{28,})\b')]
for p in paths:
    rel=p.relative_to(root).as_posix()
    if p.suffix.lower() in blocked_suffixes or any(s in rel.split('/') for s in ('data','builds','.godot','node_modules','__pycache__')):
        errors.append((rel,'private/generated path'))
    if rel in ('server/config.json','assets/network/endpoints.json','assets/network/server.crt','assets/network/easytier.json','export_presets.cfg'):
        errors.append((rel,'local deployment config'))
    if p.stat().st_size>=100*1024*1024:errors.append((rel,'GitHub individual file limit'))
    data=p.read_bytes()
    for reason,pattern in patterns:
        if re.search(pattern,data):errors.append((rel,reason))
for name,reason in errors:print(f'{name}: {reason}')
print(f'Publication audit: {len(paths)} files, {len(errors)} findings')
sys.exit(bool(errors))
