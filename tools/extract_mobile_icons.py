"""Reuse original portrait icons from the user's local map and Warcraft archives."""
import json
import extract_assets as source
root = source.ROOT
ids = ['h005','h003','h00P','h00Y','h01I','h028','h02C','h00F','h026','h004','h00R','h010','h001','h012','h01N','h01R','h027','h029']
units = {u['id']:u['fields'] for u in json.loads((root/'research/map-units.json').read_text(encoding='utf8'))}
portraits = {}
paths = []
for unit in ids:
    name = units[unit]['uico']
    path = source.extract(name)
    assert path is not None, (unit, name)
    paths.append(path)
    portraits[unit] = 'res://assets/textures/' + path.name + '.png'
source.convert_textures(paths)
(root/'assets/textures/mobile-portraits.json').write_text(json.dumps(portraits,indent=2),encoding='utf8')
(root/'research/mobile-icons-manifest.json').write_text(json.dumps(source.manifest,ensure_ascii=False,indent=2),encoding='utf8')
print('Extracted',len(portraits),'original portraits')
