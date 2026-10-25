import json,subprocess
from extract_assets import ROOT,extract,convert_textures,manifest
source=json.loads((ROOT/'research/scenery-source.json').read_text(encoding='utf-8'))
keys=['AObd_0','ZWsw_1','ZWsw_2','ZWsw_3','ZWsw_4','LOh1_0','B00C_0','B00D_0']
props=json.loads((ROOT/'research/props.json').read_text(encoding='utf-8'))
catalog=json.loads((ROOT/'assets/scenery/dynamic_models.json').read_text(encoding='utf-8'))
textures=[]
for row in source['models']:
 if row['id'] not in keys:continue
 assert not row['replacement']
 model='scenery_'+row['id'];path=extract(row['member']);assert path
 props=[a for a in props if a['id']!=model]
 props.append(dict(id=model,name=row['id'],model_file=str(path.relative_to(ROOT)),model_member=row['member'],scale=1,animation='',prop=True,scenery=True))
 catalog[row['id']]={'model':model,'tint':row['tint'],'member':row['member']}
(ROOT/'research/props.json').write_text(json.dumps(props,ensure_ascii=False,indent=2),encoding='utf-8')
for key in keys:
 model='scenery_'+key
 subprocess.run(['node',str(ROOT/'tools/convert_models.cjs'),'--only',model],cwd=ROOT,check=True)
 data=json.loads((ROOT/f'assets/models/{model}.json').read_text(encoding='utf-8'))
 assert not data['emitters'] and not data['ribbons'] and not data['lights'] and not any(c['events'] for c in data['clips'])
 for t in data['textures']:
  if t['Image']:
   path=extract(t['Image']);assert path;textures.append(path)
(ROOT/'assets/scenery/dynamic_models.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
subprocess.run(['node',str(ROOT/'tools/export_scenery_water.cjs')],cwd=ROOT,check=True)
water=json.loads((ROOT/'assets/scenery/animated_materials.json').read_text(encoding='utf-8'))
for t in water['B000_0']['textures']:
 path=extract(t['Image']);assert path;textures.append(path)
convert_textures(textures)
(ROOT/'research/scenery-idle-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('Converted',len(keys),'idle models and',len(set(textures)),'textures')
