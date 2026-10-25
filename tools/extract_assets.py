"""Extract local user's map/model dependencies; retain provenance, never write archives."""
import sys, pathlib, json, hashlib, re, struct
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,r'C:\Projects\war3-movement-lab\tools')
from mpq import read
GAME=pathlib.Path(r'C:\Games\Warcraft III Frozen Throne')
MAP=GAME/'Maps/Download/弹跳足球_1.27兼容版.w3x'
ARCHIVES=[MAP]+[GAME/x for x in ['War3Patch.mpq','War3xLocal.mpq','War3x.mpq','war3.mpq']]
manifest=[]

def safe_name(name): return re.sub(r'[^a-z0-9._-]+','_',name.lower())
def extract(name):
    name=re.sub(r'\.mdl$','.mdx',name,flags=re.I)
    for archive in ARCHIVES:
        try: data=read(archive,name)
        except FileNotFoundError: continue
        target=ROOT/'assets/source'/safe_name(name)
        target.write_bytes(data)
        manifest.append(dict(member=name,archive=str(archive),output=str(target.relative_to(ROOT)),sha256=hashlib.sha256(data).hexdigest(),bytes=len(data)))
        return target
    print('MISSING',name)
    return None

def convert_textures(paths):
    # JPEG BLP's fourth channel is alpha, not generic JPEG CMYK. Do not decode
    # these via Pillow's BLP plugin: it can invert RGB and discard the alpha.
    import subprocess, shutil
    from PIL import Image
    paths=sorted(set(paths))
    if not paths:return
    node=shutil.which('node')
    if node is None:raise RuntimeError('Node.js is needed for the Warcraft BLP decoder')
    subprocess.run([node,str(ROOT/'tools/decode_textures.cjs'),'--files',*[p.name for p in paths]],check=True)
    for p in paths:
        size=tuple(json.loads(p.with_suffix(p.suffix+'.size').read_text()))
        raw=p.with_suffix(p.suffix+'.rgba').read_bytes()
        Image.frombytes('RGBA',size,raw).save(ROOT/'assets/textures'/(p.name+'.png'))

def parse_units():
    b=read(MAP,'war3map.w3u');p=4;units=[]
    def string():
        nonlocal p
        end=b.index(0,p);raw=b[p:end];p=end+1
        try:return raw.decode('utf8')
        except UnicodeDecodeError:return raw.decode('gb18030',errors='replace')
    for table in range(2):
        count=struct.unpack_from('<I',b,p)[0];p+=4
        for _ in range(count):
            base,new,n=struct.unpack_from('<4s4si',b,p);p+=12;fields={}
            for _ in range(n):
                key,typ=struct.unpack_from('<4si',b,p);p+=8
                if typ==3: value=string()
                else:value=struct.unpack_from('<i' if typ==0 else '<f',b,p)[0];p+=4
                fields[key.decode()]=value;p+=4
            units.append(dict(id=(new if table else base).decode(),base=base.decode(),fields=fields))
    assert p==len(b)
    return units

if __name__=='__main__':
    if '--textures' in sys.argv:
        manifest=json.loads((ROOT/'research/assets-manifest.json').read_text(encoding='utf8'))
        textures=[]
        for model_path in (ROOT/'assets/models').glob('*.json'):
            model=json.loads(model_path.read_text(encoding='utf8'))
            for t in model['textures']:
                if not t.get('Image'):continue
                path=extract(t['Image'])
                if path:textures.append(path)
        convert_textures(textures)
    else:
        units=parse_units();actors=[]
        for u in units:
            f=u['fields']
            if u['id']=='h000' or 'giant' in f.get('utyp',''):
                model=f.get('umdl','')
                if not model:continue
                path=extract(model)
                actors.append(dict(id=u['id'],name=re.sub(r'\|c[0-9a-fA-F]{8}|\|r','',f.get('unam',u['id'])).strip(),model_file=str(path.relative_to(ROOT)) if path else None,model_member=model,scale=f.get('usca',1),animation=f.get('uani',''),speed=f.get('umvs',300),turn=f.get('umvr',.6),collision=f.get('ucol',30),abilities=f.get('uabi','')))
        (ROOT/'research/actors.json').write_text(json.dumps(actors,ensure_ascii=False,indent=2),encoding='utf8')
        (ROOT/'research/map-units.json').write_text(json.dumps(units,ensure_ascii=False,indent=2),encoding='utf8')
        for name in ['TerrainArt\\LordaeronSummer\\Lords_Grass.blp','TerrainArt\\LordaeronSummer\\Lords_Dirt.blp']:
            extract(name)
        for name in ['war3map.j','war3map.w3a','war3map.w3e','war3map.wpm','war3map.w3b','war3map.doo','war3map.w3d']:
            (ROOT/'research'/name).write_bytes(read(MAP,name))
    # Paths repeated across models share identical source; retain one provenance entry.
    manifest=list({x['member'].lower():x for x in manifest}.values())
    (ROOT/'research/assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    print('Extracted',len(manifest),'unique local assets')
