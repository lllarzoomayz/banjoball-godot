"""Decode the original replaceable team glow without inventing a solid color quad."""
import json
from pathlib import Path
from extract_assets import ROOT, extract, manifest, convert_textures
manifest.extend(json.loads((ROOT/'research/assets-manifest.json').read_text(encoding='utf8')))
asset = extract(r'ReplaceableTextures\TeamGlow\TeamGlow00.blp')
if asset is None:
    raise RuntimeError('Original team glow was not found in the local game archives')
convert_textures([asset])
(ROOT/'research/assets-manifest.json').write_text(json.dumps(list({x['member'].lower():x for x in manifest}.values()),ensure_ascii=False,indent=2),encoding='utf8')
print(asset.name)
