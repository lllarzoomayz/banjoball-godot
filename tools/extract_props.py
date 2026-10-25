"""Extract original skill props, leaving player roster and source map untouched."""
import json,re,sys
from extract_assets import ROOT,extract,manifest,convert_textures
manifest.extend(json.loads((ROOT/'research/assets-manifest.json').read_text(encoding='utf8')))
units=json.loads((ROOT/'research/map-units.json').read_text(encoding='utf8'))
props=[]
for unit in units:
    if unit['id'] not in ['h02D','h011','h01S','h02E','h02A','h00T','h00E','h00H','h02B']:continue
    fields=unit['fields']
    source=extract(fields['umdl'])
    if source is None:raise RuntimeError('Missing local prop model: '+unit['id'])
    props.append(dict(id=unit['id'],name=fields['unam'],model_file=str(source.relative_to(ROOT)),model_member=fields['umdl'],scale=fields.get('usca',1),animation='',prop=True))
(ROOT/'research/props.json').write_text(json.dumps(props,ensure_ascii=False,indent=2),encoding='utf8')
textures=[]
for prop in props:
    if '--models-only' in sys.argv:continue
    model=ROOT/'assets/models'/(prop['id']+'.json')
    if not model.exists():continue
    for texture in json.loads(model.read_text(encoding='utf8'))['textures']:
        if not texture['Image']:continue
        source=extract(texture['Image'])
        if source is None:raise RuntimeError('Missing prop texture: '+texture['Image'])
        textures.append(source)
convert_textures(textures)
(ROOT/'research/assets-manifest.json').write_text(json.dumps(list({x['member'].lower():x for x in manifest}.values()),ensure_ascii=False,indent=2),encoding='utf8')
