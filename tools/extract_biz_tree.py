"""Original one-per-map BizTree easter egg: candidates, two units and textures."""
from pathlib import Path
import json,re,subprocess
from extract_assets import ROOT,extract,convert_textures,manifest
from extract_scenery import placements

script=(ROOT/'research/war3map.j').read_text(encoding='utf-8')
# The initial camera bounds include margins; InitBlizzard expands them back to
# these four map-playable limits before later per-field camera restrictions.
bounds=[-7552.0,-4480.0,15744.0,27008.0]
assert 'SetCameraBounds(-7552.0+GetCameraMargin' in script
assert '15744.0-GetCameraMargin' in script and '27008.0-GetCameraMargin' in script
units=json.loads((ROOT/'research/map-units.json').read_text(encoding='utf-8'))
props=json.loads((ROOT/'research/props.json').read_text(encoding='utf-8'))
for unit in units:
    if unit['id'] not in ['h01K','h01L']:continue
    f=unit['fields'];src=extract(f['umdl']);assert src
    row=dict(id=unit['id'],name='Biz Tree',model_file=str(src.relative_to(ROOT)),model_member=f['umdl'],scale=f['usca'],animation='',prop=True)
    props=[p for p in props if p['id']!=row['id']]+[row]
(ROOT/'research/props.json').write_text(json.dumps(props,ensure_ascii=False,indent=2),encoding='utf-8')
textures=[]
for id in ['h01K','h01L']:
    subprocess.run(['node',str(ROOT/'tools/convert_models.cjs'),'--only',id],cwd=ROOT,check=True)
    data=json.loads((ROOT/f'assets/models/{id}.json').read_text(encoding='utf-8'))
    assert not any(c.get('events') for c in data['clips'])
    for t in data['textures']:
        if t['Image']:
            path=extract(t['Image']);assert path and path.stat().st_size;textures.append(path)
convert_textures(textures)
trees=[p for p in placements() if p['id'] in ['LTlt','WTst'] and bounds[0]<=p['position'][0]<=bounds[2] and bounds[1]<=p['position'][1]<=bounds[3]]
assert all(p['flags']&2 for p in trees)
catalog={'source':'BizTree__init/select/disappear in original war3map.j','bounds':bounds,'draws':3,'delay':.5,'text_lifetime':1.5,'replacement_scale':2.3,'replacement_angle':270,'replacement_variation':6,
         'candidates':[dict(editor_id=p['editor_id'],type=p['id'],position=p['position'],model='h01K' if p['id']=='LTlt' else 'h01L',replacement=p['id']+'_6') for p in trees]}
(ROOT/'assets/scenery/biz_trees.json').write_text(json.dumps(catalog,ensure_ascii=False),encoding='utf-8')
(ROOT/'research/biz-tree-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('Eligible original trees',len(trees),'original textures',len(textures))
