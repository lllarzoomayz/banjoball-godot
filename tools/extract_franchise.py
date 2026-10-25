"""Extract the five original Franchise logo/banner pairs and their source placements."""
import json, subprocess
from extract_assets import ROOT, extract, manifest, convert_textures
from extract_scenery import modified_table

table=modified_table(r'Units\DestructableData.slk',r'Units\DestructableMetaData.slk','w3b')
names=['Capital City Centipedes','Dalaran Dinos','Pandaria Brewmasters','Ashara Aces','Winterspring Weasels']
short=['蜈蚣队','恐龙队','酒仙队','王牌队','雪貂队']
colors=[1,0,5,2,6]
# Original Warcraft player colors, matching Franchise__color / GetColorCode.
rgb=['0041ff','ff0202','fe8a0e','1ce6b9','20c000']
logos=['B007','B008','B009','B00A','B00B'];banners=['B00E','B00F','B00G','B00H','B00I']
props_file=ROOT/'research/props.json';props=json.loads(props_file.read_text(encoding='utf-8'))
models={};textures=[]
for raw in logos+banners:
    row=table[raw];member=row['file'].removesuffix('.mdl')+'.mdx';source=extract(member);assert source,member
    name='franchise_'+raw.lower();props=[p for p in props if p['id']!=name]
    props.append(dict(id=name,name=raw+' Franchise',model_file=str(source.relative_to(ROOT)),model_member=member,scale=1,animation='',prop=True,source_bounds=True))
    models[raw]=dict(model=name,source=row)
props_file.write_text(json.dumps(props,ensure_ascii=False,indent=2),encoding='utf-8')
for raw,row in models.items():
    subprocess.run(['node',str(ROOT/'tools/convert_models.cjs'),'--only',row['model']],cwd=ROOT,check=True)
    data=json.loads((ROOT/'assets/models'/f"{row['model']}.json").read_text(encoding='utf-8'))
    row['clips']=[c['name'] for c in data['clips']]
    for tex in data['textures']:
        if tex['Image']:textures.append(extract(tex['Image']))
convert_textures(textures)
world=json.loads((ROOT/'assets/scenery/apocalypse-world.json').read_text(encoding='utf-8'))
catalog=dict(teams=[dict(name=names[i],short=short[i],color_index=colors[i],color=rgb[i],logo=logos[i],banner=banners[i]) for i in range(5)],models=models,
             placeholders=[p for p in world['placed'] if p['id'] in ['B006','B00C','B00D']],
             source='war3map.j Franchise__showFranchiseLogos / Franchise__changeColor / StartFranchise')
(ROOT/'assets/scenery/franchise.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'research/franchise-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('Franchise models:',{raw:row['clips'] for raw,row in models.items()},'placeholders:',len(catalog['placeholders']))
