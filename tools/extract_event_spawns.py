"""Map-first SPN dependencies, preserving empty map overrides."""
import json,subprocess
from extract_assets import ROOT,extract,convert_textures,manifest

definitions=json.loads((ROOT/'research/model-event-definitions.json').read_text(encoding='utf-8'))['definitions']
actors=[];catalog={};textures=[]
for row in definitions:
    if row['type']!='SPN':continue
    code=row['code'];member=row['definition']['Model'];source=extract(member)
    key='ev_spawn_'+code.lower()
    if source is None:
        catalog[code]={'model':'','source':row['definition'],'missing':True,'empty_override':False}
        continue
    catalog[code]={'model':key if source.stat().st_size else '', 'source':row['definition'], 'empty_override':source.stat().st_size==0}
    if not source.stat().st_size:continue
    actors.append(dict(id=key,name=code,model_file=str(source.relative_to(ROOT)),model_member=member,scale=1,animation='',prop=True,effect=True,event_spawn=True))
(ROOT/'research/event-spawn-assets.json').write_text(json.dumps(actors,indent=2),encoding='utf-8')
for actor in actors:
    subprocess.run(['node',str(ROOT/'tools/convert_models.cjs'),'--only',actor['id']],check=True,cwd=ROOT)
    data=json.loads((ROOT/'assets/models'/f"{actor['id']}.json").read_text(encoding='utf-8'))
    # Known nested events use the existing catalog; never silently drop a new
    # dependency. Recursive SPN needs cycle validation before enabling it.
    known={(r['type'],r['code']) for r in definitions}
    for clip in data['clips']:
        for event in clip.get('events',[]):
            if event['type']=='SPN' or (event['type'],event['code']) not in known:
                raise ValueError('Nested spawn dependency needs extraction: '+str(event))
    for texture in data['textures']:
        if not texture.get('Image'):continue
        path=extract(texture['Image'])
        if path is None:raise FileNotFoundError(texture['Image'])
        if path.stat().st_size==0:raise ValueError('Empty spawn texture requires explicit suppression: '+texture['Image'])
        textures.append(path)
convert_textures(textures)
(ROOT/'assets/models/events/spawns.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
(ROOT/'research/event-spawn-assets-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Spawn codes',len(catalog),'models',len(actors),'unique textures',len(set(textures)))
