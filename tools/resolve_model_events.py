"""Resolve audited original MDX event codes against the locally installed game tables."""
import sys,json,hashlib
from pathlib import Path
from extract_assets import ROOT,ARCHIVES,read
from extract_scenery import slk
base=ROOT/'research/model-event-tables';base.mkdir(exist_ok=True)
records=[];tables={}
for member in [r'UI\SoundInfo\AnimLookups.slk',r'UI\SoundInfo\AnimSounds.slk',r'Splats\SpawnData.slk',r'Splats\SplatData.slk',r'Splats\UberSplatData.slk']:
    for archive in ARCHIVES:
        try:data=read(archive,member)
        except FileNotFoundError:continue
        target=base/member.split('\\')[-1];target.write_bytes(data)
        tables[target.stem]=slk(target)
        records.append({'member':member,'archive':str(archive),'sha256':hashlib.sha256(data).hexdigest(),'file':str(target.relative_to(ROOT))})
        break
    else:raise FileNotFoundError(member)
(base/'sources.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
d=json.loads((ROOT/'research/model-events-inventory.json').read_text());missing=[];codes={}
for model in d['models']:
    for e in model['events']:
        table={'SND':'AnimLookups','FPT':'SplatData','SPL':'SplatData','SPN':'SpawnData','UBR':'UberSplatData'}.get(e['type'])
        if table is None:continue # Unrecognized event names (e.g. Point01) have no native catalog handler.
        row=tables[table].get(e['code']);key=e['type']+':'+e['code']
        if key not in codes:
            entry={'type':e['type'],'code':e['code'],'table':table,'definition':row,'models':[],'status':'definition_found' if row else 'definition_missing'}
            if e['type']=='SND' and row:entry['sound_definition']=tables['AnimSounds'].get(row['SoundLabel'])
            codes[key]=entry
        codes[key]['models'].append({'id':model['id'],'reachable_in_exported_clip':e['reachable_in_exported_clip']})
        if not row:missing.append((model['id'],e['name']))
report={'scope':'Source definition inventory; runtime coverage is tracked separately in effect-coverage-audit.json.','definitions':list(codes.values()),'missing':missing,'missing_sound_definitions':[k for k,v in codes.items() if v['type']=='SND' and not v.get('sound_definition')]}
(ROOT/'research/model-event-definitions.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('Unique event codes',len(codes),'missing table entries',len(missing),'missing sound definitions',len(report['missing_sound_definitions']))
