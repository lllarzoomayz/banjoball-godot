"""Stage only runtime resources, import, export and verify a local signed APK."""
from pathlib import Path
import hashlib, json, os, re, secrets, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(os.environ.get('BANJO_TOOLCHAIN', ROOT / '.local/toolchain'))
SDK = TOOLS / 'android-build/sdk'
JAVA = TOOLS / 'jdk/jdk-21.0.12.1+1'
GODOT = TOOLS / 'Godot_v4.6.1-stable_win64_console.exe'
STAGE = ROOT / '.local/android-stage'
OUT = ROOT / 'builds/android'
KEYS = TOOLS / 'android-build/signing'
for path in [STAGE, OUT, KEYS]:path.mkdir(parents=True, exist_ok=True)
env = os.environ.copy();env['JAVA_HOME'] = str(JAVA)
env['PATH'] = str(JAVA / 'bin') + os.pathsep + env['PATH']
emulator = '--emulator' in sys.argv

def run(args, log):
    if emulator:log='emulator-'+log
    print('Running', log, flush=True)
    with (OUT / log).open('w', encoding='utf-8') as stream:
        si=subprocess.STARTUPINFO();si.dwFlags|=subprocess.STARTF_USESHOWWINDOW;si.wShowWindow=0
        result = subprocess.run([str(x) for x in args], env=env, cwd=STAGE, stdout=stream, stderr=subprocess.STDOUT, startupinfo=si)
    if result.returncode:
        raise RuntimeError(f'{log}: exit {result.returncode}; see {OUT / log}')
    text = (OUT / log).read_text(encoding='utf-8', errors='replace')
    if re.search(r'^\s*(?:SCRIPT ERROR|ERROR):', text, re.M):
        raise RuntimeError(f'{log}: Godot reported errors')

settings = Path(os.environ['APPDATA']) / 'Godot/editor_settings-4.6.tres'
backup = TOOLS / 'android-build/editor_settings-4.6.before-android.tres'
if not backup.exists():shutil.copy2(settings, backup)
config = settings.read_text(encoding='utf-8')
for key,value in [('java_sdk_path',JAVA),('android_sdk_path',SDK)]:
    setting = f'export/android/{key}'
    line = f'{setting} = "{value.as_posix()}"'
    if re.search(r'^'+re.escape(setting)+r' = .*$', config, re.M):
        config = re.sub(r'^'+re.escape(setting)+r' = .*$', lambda _:line, config, flags=re.M)
    else:config += '\n' + line + '\n'
settings.write_text(config, encoding='utf-8')

keyfile = KEYS / 'local-release.keystore'
secret = KEYS / 'local-signing.json'
if not secret.exists():secret.write_text(json.dumps({'alias':'banjoball','password':secrets.token_urlsafe(30)}),encoding='utf-8')
credential = json.loads(secret.read_text(encoding='utf-8'))
env['BANJOBALL_STORE_PASSWORD'] = credential['password']
if not keyfile.exists():
    run([JAVA/'bin/keytool.exe','-genkeypair','-keystore',keyfile,'-alias',credential['alias'],'-keyalg','RSA','-keysize','3072','-validity','10000','-storepass:env','BANJOBALL_STORE_PASSWORD','-keypass:env','BANJOBALL_STORE_PASSWORD','-dname','CN=Banjoball Local Build, O=Local Development, C=CN'], 'signing-setup.log')
env['GODOT_ANDROID_KEYSTORE_RELEASE_PATH'] = str(keyfile)
env['GODOT_ANDROID_KEYSTORE_RELEASE_USER'] = credential['alias']
env['GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD'] = credential['password']

sources = [ROOT/'project.godot',ROOT/'main.tscn',ROOT/'THIRD_PARTY.txt',ROOT/'assets/app_icon.svg']
for folder in ['bin','scripts','addons/webrtc_native','assets/models','assets/scenery','assets/textures','assets/fonts','assets/audio','assets/i18n','assets/network']:
    sources += [p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix not in ['.import','.uid'] and 'easytier' not in p.relative_to(ROOT).parts and p.name!='easytier.json']
for name in ['actors.json','fields.json','authored-pathing.json','native-math-tables.json','lightning-assets.json']:
    sources.append(ROOT/'research'/name)
for source in sources:
    target = STAGE/source.relative_to(ROOT);target.parent.mkdir(parents=True, exist_ok=True);shutil.copy2(source,target)
project=(STAGE/'project.godot').read_text(encoding='utf-8')
project=project.replace('config/name="弹跳足球 · 3D 还原试作"','config/name="弹跳足球3D"\nconfig/icon="res://assets/app_icon.svg"')
(STAGE/'project.godot').write_text(project,encoding='utf-8')

preset='''[preset.0]
name="Android"
platform="Android"
runnable=true
advanced_options=true
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.wc3anim,*.deathanim,THIRD_PARTY.txt,*.crt,assets/network/easytier-licenses/*.txt"
exclude_filter=""
export_path=""
script_export_mode=2

[preset.0.options]
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/export_format=0
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code=46
version/name="0.4.41"
package/unique_name="org.local.banjoball3d"
package/name="弹跳足球3D"
package/signed=true
launcher_icons/main_192x192="res://assets/app_icon.svg"
launcher_icons/adaptive_foreground_432x432="res://assets/app_icon.svg"
screen/immersive_mode=true
screen/edge_to_edge=false
user_data_backup/allow=false
permissions/internet=true
permissions/access_network_state=true
permissions/change_wifi_multicast_state=true
permissions/read_external_storage=false
permissions/write_external_storage=false
'''
(STAGE/'export_presets.cfg').write_text(preset,encoding='utf-8')
if emulator:
    preset=preset.replace('architectures/armeabi-v7a=true','architectures/armeabi-v7a=false').replace('architectures/arm64-v8a=true','architectures/arm64-v8a=false').replace('architectures/x86_64=false','architectures/x86_64=true')
    (STAGE/'export_presets.cfg').write_text(preset,encoding='utf-8')
run([GODOT,'--headless','--editor','--path',STAGE,'--import','--quit'], 'android-import.log')
apk=OUT/('Banjoball-3D-emulator-0.4.41.apk' if emulator else 'Banjoball-3D-Android-0.4.41.apk')
run([GODOT,'--headless','--path',STAGE,'--export-release','Android',apk], 'android-export.log')
buildtools=SDK/'build-tools/35.0.1'
run([buildtools/'apksigner.bat','verify','--verbose','--print-certs',apk], 'apk-signature.txt')
run([buildtools/'aapt.exe','dump','badging',apk], 'apk-manifest.txt')
run([buildtools/'zipalign.exe','-c','-P','16','-v','4',apk], 'apk-alignment.txt')
manifest={'apk':apk.name,'sha256':hashlib.file_digest(apk.open('rb'),'sha256').hexdigest(),'bytes':apk.stat().st_size,'version':'0.4.41','godot':'4.6.1','source_files':len(sources),'signing_key':str(keyfile),'stage':str(STAGE)}
(OUT/('emulator-build-info.json' if emulator else 'build-info.json')).write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/(apk.name+'.sha256')).write_text(manifest['sha256']+'  '+apk.name+'\n',encoding='utf-8')
print('APK ready:',apk,apk.stat().st_size,flush=True)
