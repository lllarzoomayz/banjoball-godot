"""Local MPQ-only spell extraction; do not modify the map or roster."""
import json, re, sys, shutil
from extract_assets import ROOT, extract, manifest

manifest.extend(json.loads((ROOT/'research/assets-manifest.json').read_text(encoding='utf8')))
from extract_scenery import slk
lightning=slk(extract('Splats\\LightningData.slk'))
selected={k:lightning[k] for k in ['BKHL','DRAL','ROPE','RIFT','LINK','SWAP']}
for row in selected.values():
    name=row['Dir']+'\\'+row['file']
    if not name.lower().endswith('.blp'):name+='.blp'
    if extract(name) is None: raise RuntimeError(name)
    row['texture']=name
(ROOT/'research/lightning-assets.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2),encoding='utf8')
out=ROOT/'research/spell-assets.json'
if '--textures' in sys.argv:
    for model in (ROOT/'assets/models').glob('*.json'):
        data=json.loads(model.read_text(encoding='utf8'))
        for texture in data['textures']:
            name=texture.get('Image')
            if name and not (ROOT/'assets/source'/re.sub(r'[^a-z0-9._-]+','_',name.lower())).exists():
                if extract(name) is None: raise RuntimeError(name)
else:
    script=(ROOT/'research/war3map.j').read_text(encoding='utf8')
    names=['PLAYER_BUMP','GOAL_BLOCK','SLAM','SHADOW','SMASH','POWERSHOT','POWERSHOT_BLAST',
           'POWERSHOT_CHARGE','ANGELIC_KICK','CURVESHOT','POSSESS','POSSESS_EJECT',
           'SWAP_CASTER','SWAP_TARGET','METAMORPH','JUMP','EARTH_PILLAR','EARTH_PILLAR_END','HOOK','BALL_BUMP']
    entries=[e for e in json.loads(out.read_text(encoding="utf8")) if e.get("buff") or e.get("ability")] if out.exists() else []
    for name in names:
        member=re.search(r'constant string '+name+r'_SFX_PATH="([^"]+)"',script).group(1).replace('\\\\','\\')
        source=extract(member)
        if source is None: raise RuntimeError(member)
        entries.append(dict(id='fx_'+name.lower(),name=name,model_file=str(source.relative_to(ROOT)),model_member=member,scale=1,animation='',prop=True,effect=True))
    unit=next(u for u in json.loads((ROOT/'research/map-units.json').read_text(encoding='utf8')) if u['id']=='h002')
    member=unit['fields']['umdl'];source=extract(member)
    entries.append(dict(id='fx_black_hole',name='BLACK_HOLE',model_file=str(source.relative_to(ROOT)),model_member=member,scale=1,animation='',prop=True,effect=True))
    member=r'Abilities\Spells\Other\TalkToMe\TalkToMe.mdl'
    source=extract(member)
    if source is None:raise RuntimeError(member)
    entries.append(dict(id='fx_pass_me',name='PASS_ME',model_file=str(source.relative_to(ROOT)),model_member=member,scale=1,animation='',prop=True,effect=True,source_function='PassMe___cast'))
    entries=[e for e in entries if e['id'] not in ['fx_shout','fx_adrenaline']]
    abilities={a['id']:a['fields'] for a in json.loads((ROOT/'research/abilities.json').read_text(encoding='utf8'))}
    buffs={a['id']:a['fields'] for a in json.loads((ROOT/'research/map-buffs.json').read_text(encoding='utf8'))}
    for id,member,owner in [('fx_shout',abilities['A00S']['acat_0'],{'ability':'A00S'}),('fx_adrenaline',buffs['B00B']['ftat'],{'buff':'B00B'})]:
        source=extract(member)
        if source is None:raise RuntimeError(member)
        entries.append(dict(id=id,name=id.upper(),model_file=str(source.relative_to(ROOT)),model_member=member,scale=1,animation='',prop=True,effect=True,**owner))
    for number in range(1,6):
        member=rf'war3mapImported\death{number} [High quality].mp3'
        source=extract(member)
        if source is None:raise RuntimeError(member)
        shutil.copyfile(source,ROOT/f'assets/audio/shout{number}.mp3')
    out.write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf8')
manifest=list({x['member'].lower():x for x in manifest}.values())
(ROOT/'research/assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print('Local spell assets ready')
