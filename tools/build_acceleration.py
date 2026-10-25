"""Reproducible native hot-loop builds; never runs more than one SCons build."""
from pathlib import Path
import os, subprocess, sys, hashlib, json
ROOT=Path(__file__).resolve().parents[1]
TOOLS=Path(os.environ.get('BANJO_TOOLCHAIN',ROOT/'.local/toolchain'))
env=os.environ.copy()
env['BANJO_GODOT_CPP']=str(TOOLS/'godot-cpp')
env['ANDROID_HOME']=str(TOOLS/'android-build/sdk')
targets=[('windows','x86_64'),('android','arm64'),('android','arm32'),('android','x86_64')]
if '--windows' in sys.argv:targets=targets[:1]
if '--android' in sys.argv:targets=targets[1:]
results=[]
for platform,arch in targets:
    args=[sys.executable,'-m','SCons','-C','native',f'platform={platform}',f'arch={arch}','target=template_release','build_profile=build_profile.json','lto=none','-j8']
    if platform=='windows':args+=['use_mingw=yes','use_llvm=yes',f'mingw_prefix={(TOOLS/"llvm-mingw-20261020-ucrt-x86_64").as_posix()}']
    print('Building',platform,arch,flush=True)
    log=ROOT/f'research/native-{platform}-{arch}-build.log'
    with log.open('w') as stream:
        result=subprocess.run(args,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT)
    if result.returncode:raise RuntimeError(f'Build failed: {log}')
    revision='.049' if platform=='windows' else ''
    binary=ROOT/f'bin/libbanjo{revision}.{platform}.{arch}.{"dll" if platform=="windows" else "so"}'
    assert binary.is_file()
    results.append({'platform':platform,'arch':arch,'bytes':binary.stat().st_size,'sha256':hashlib.file_digest(binary.open('rb'),'sha256').hexdigest()})
(ROOT/'research/native-build-info.json').write_text(json.dumps(results,indent=2))
print('Native libraries ready',flush=True)
