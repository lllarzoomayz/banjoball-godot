"""Compose the original W3E ground tiles, retaining corner blend masks/variants.

No image generation: every texel comes from the local game's BLP atlases.
Atlas layout reference: mdx-m3-viewer w3x ground.vert.ts and getVariation.
"""
import json
from PIL import Image
from extract_assets import ROOT, safe_name

source = json.loads((ROOT/'research/scenery-source.json').read_text(encoding='utf8'))
conversion = json.loads((ROOT/'research/scenery-conversion.json').read_text(encoding='utf8'))
decoded = ROOT/'research/scenery-decoded'
for texture in json.loads((decoded/'index.json').read_text(encoding='utf8')):
    image = Image.frombytes('RGBA',(texture['width'],texture['height']),(decoded/(texture['name']+'.rgba')).read_bytes())
    image.save(ROOT/'assets/textures'/(texture['name']+'.png'))
models = {m['id']: m for m in conversion['models'] if m['meshes'] > 0}
dynamic_path=ROOT/'assets/scenery/dynamic_models.json'
if dynamic_path.exists():models.update(json.loads(dynamic_path.read_text(encoding='utf-8')))
out = ROOT/'assets/scenery'
atlases = [Image.open(ROOT/'assets/textures'/(safe_name(t['member'])+'.png')).convert('RGBA')
           for t in source['fields'][0]['tile_assets']]
cache = {}


def tile(texture, cell):
    key = (texture, cell)
    if key not in cache:
        atlas = atlases[texture]; size = atlas.height//4
        x = cell % 4 + (4 if cell >= 16 else 0)
        y = (cell % 16)//4
        cache[key] = atlas.crop((x*size,y*size,(x+1)*size,(y+1)*size)).resize((64,64),Image.Resampling.BILINEAR)
    return cache[key]


reports = []
for field in source['fields']:
    nx, ny = field['grid']; corners = field['corners']
    image = Image.new('RGB',((nx-1)*64,(ny-1)*64))
    for y in range(ny-1):
        for x in range(nx-1):
            c = [corners[y*nx+x], corners[y*nx+x+1], corners[(y+1)*nx+x], corners[(y+1)*nx+x+1]]
            textures = sorted(set(v['ground'] for v in c))
            base = textures[0]; variation = c[0]['variation']
            if atlases[base].width > atlases[base].height:
                cell = variation+16 if variation<16 else (15 if variation==16 else 0)
            else: cell = 0 if variation==0 else 15
            result = tile(base,cell).convert('RGB')
            for texture in textures[1:]:
                mask = sum(bit for v,bit in zip(c,[2,1,8,4]) if v['ground']==texture)
                overlay = tile(texture,mask)
                result.paste(overlay,(0,0),overlay.getchannel('A'))
            image.paste(result,(x*64,(ny-2-y)*64))
    filename = field['id']+'_ground.png'
    image.save(out/filename)
    data = dict(id=field['id'], bounds=field['bounds'], grid=field['grid'],
                heights=[c['height']-field['base_height'] for c in corners],
                texture='res://assets/scenery/'+filename,
                placements=[d for d in field['placements'] if d['key'] in models])
    (out/(field['id']+'.json')).write_text(json.dumps(data,ensure_ascii=False),encoding='utf8')
    reports.append(dict(id=field['id'], placements=len(data['placements']), source_placements=len(field['placements']),
                        model_variants=len(set(d['key'] for d in data['placements'])), texture_size=image.size,
                        height_range=[min(data['heights']),max(data['heights'])]))
    print(reports[-1])
(ROOT/'research/field-scenery-report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf8')
# Preserve detail at oblique camera angles without foliage/ground shimmering.
imports = list(out.glob('*.png.import'))
imports += [ROOT/'assets/textures'/(t['name']+'.png.import') for t in json.loads((decoded/'index.json').read_text(encoding='utf8'))]
for path in imports:
    if path.exists():
        path.write_text(path.read_text(encoding='utf8').replace('mipmaps/generate=false','mipmaps/generate=true'),encoding='utf8')
