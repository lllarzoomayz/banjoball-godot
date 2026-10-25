"""Export source SLK decal definitions, recursively including water variants."""
import json,hashlib
from extract_assets import ROOT,extract,convert_textures,manifest
from extract_scenery import slk,terrain

source=json.loads((ROOT/'research/model-event-definitions.json').read_text(encoding='utf-8'))['definitions']
splats=slk(ROOT/'research/model-event-tables/SplatData.slk')
rows={};textures={};missing=[];queue=[(r['type'],r['code'],r['definition']) for r in source if r['type'] in ['FPT','SPL','UBR']]
while queue:
    kind,code,data=queue.pop(0);key=kind+':'+code
    if key in rows:continue
    member=data['Dir']+'\\'+data['file']+'.blp'
    if member not in textures:
        path=extract(member)
        if path is None:missing.append(member);textures[member]=None
        elif path.stat().st_size==0:textures[member]=None
        else:textures[member]=path
    path=textures[member]
    rows[key]={'kind':kind,'code':code,'source':data,'texture':('res://assets/textures/'+path.name+'.png') if path else '', 'texture_member':member,'texture_unavailable':path is None}
    water=data.get('Water','NULL')
    if water not in ['NULL','',None]:
        if water not in splats:raise ValueError('Missing water substitute '+water)
        queue.append(('SPL',water,splats[water]))
convert_textures([p for p in textures.values() if p])
# Use a distinct subfolder: model converters enumerate root *.json as models.
target=ROOT/'assets/models/events/decals.json';target.parent.mkdir(exist_ok=True)
land=terrain()
report={'definitions':rows,'terrain_native_water_vertices':sum(bool(c['flags']&64) for c in land['corners']), 'note':'No native W3E water flags in this map; generated WaterPlane scenery does not change terrain classification.'}
target.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'research/event-decal-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'research/event-decal-extraction.json').write_text(json.dumps({'codes':len(rows),'textures':len(textures),'missing':missing,'native_water_vertices':report['terrain_native_water_vertices']},indent=2),encoding='utf-8')
if missing:raise FileNotFoundError(missing)
print('Decal codes',len(rows),'textures',len(textures),'water vertices',report['terrain_native_water_vertices'])
