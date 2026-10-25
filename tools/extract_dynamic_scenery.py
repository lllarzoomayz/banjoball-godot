"""Convert original placed scenery with particle/UV animation to runtime MDX models."""
import json,subprocess
from extract_assets import ROOT,extract,convert_textures,manifest

source=json.loads((ROOT/'research/scenery-source.json').read_text(encoding='utf-8'))
props=json.loads((ROOT/'research/props.json').read_text(encoding='utf-8'))
keys=['D000_0','LOo1_1','D002_0']
catalog_path=ROOT/'assets/scenery/dynamic_models.json'
catalog=json.loads(catalog_path.read_text(encoding='utf-8')) if catalog_path.exists() else {}
for row in source['models']:
    if row['id'] not in keys:continue
    assert not row['replacement'], 'New replacement texture semantics need explicit conversion'
    path=extract(row['member']);assert path
    model='scenery_'+row['id']
    props=[a for a in props if a['id']!=model]
    props.append(dict(id=model,name=row['id'],model_file=str(path.relative_to(ROOT)),model_member=row['member'],scale=1,animation='',prop=True,scenery=True))
    catalog[row['id']]={'model':model,'tint':row['tint'],'member':row['member']}
(ROOT/'research/props.json').write_text(json.dumps(props,ensure_ascii=False,indent=2),encoding='utf-8')
textures=[]
for key in keys:
    row=catalog[key]
    subprocess.run(['node',str(ROOT/'tools/convert_models.cjs'),'--only',row['model']],cwd=ROOT,check=True)
    data=json.loads((ROOT/f"assets/models/{row['model']}.json").read_text(encoding='utf-8'))
    assert not any(c.get('events') for c in data['clips'])
    for t in data['textures']:
        if t['Image']:
            p=extract(t['Image']);assert p and p.stat().st_size;textures.append(p)
convert_textures(textures)
(ROOT/'assets/scenery/dynamic_models.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
placements=[]
for field in source['fields']:
    path=ROOT/f"assets/scenery/{field['id']}.json"
    data=json.loads(path.read_text(encoding='utf-8'))
    # Static baking originally discarded meshless Steamcloud. Restore only the
    # known dynamic placements, with original coordinates, scale and ordering.
    existing={(p['key'],p['editor_id']) for p in data['placements']}
    added=[p for p in field['placements'] if p['key'] in catalog and (p['key'],p['editor_id']) not in existing]
    data['placements'].extend(added)
    path.write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8')
    placements.append({'field':field['id'],'restored_meshless':len(added),'dynamic':sum(p['key'] in catalog for p in data['placements'])})
(ROOT/'research/dynamic-scenery-placements.json').write_text(json.dumps(placements,indent=2),encoding='utf-8')
(ROOT/'research/dynamic-scenery-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('Dynamic source models',len(catalog),'unique textures',len(set(textures)))
