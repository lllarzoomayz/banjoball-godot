"""Resolve scripted B001..B005 from the local map rather than inventing ice art."""
import json,subprocess
from extract_assets import ROOT,extract,manifest,convert_textures
from extract_scenery import modified_table

def main():
    table=modified_table(r'Units\DestructableData.slk',r'Units\DestructableMetaData.slk','w3b')
    props_path=ROOT/'research/props.json';props=json.loads(props_path.read_text(encoding='utf-8'))
    catalog={};textures=[]
    for raw in ['B001','B002','B003','B004','B005']:
        row=table[raw];member=row['file'].removesuffix('.mdl')+'.mdx';source=extract(member);assert source
        name='ice_'+raw.lower();props=[p for p in props if p['id']!=name]
        props.append(dict(id=name,name=raw+' scripted ice',model_file=str(source.relative_to(ROOT)),model_member=member,scale=1,animation='',prop=True))
        catalog[raw]=dict(model=name,source=row)
    props_path.write_text(json.dumps(props,ensure_ascii=False,indent=2),encoding='utf-8')
    for raw,row in catalog.items():
        subprocess.run(['node',str(ROOT/'tools/convert_models.cjs'),'--only',row['model']],cwd=ROOT,check=True)
        model=json.loads((ROOT/'assets/models'/f"{row['model']}.json").read_text(encoding='utf-8'))
        row['clips']=[c['name'] for c in model['clips']]
        row['has_death']=any(c.lower().startswith('death') for c in row['clips'])
        for texture in model['textures']:
            if texture['Image']:textures.append(extract(texture['Image']))
    convert_textures(textures)
    audio_path=ROOT/'assets/audio/scenery-events/catalog.json'
    audio=json.loads(audio_path.read_text(encoding='utf-8'))
    for raw,row in catalog.items():
        label=row['source']['deathSnd'];assert label in audio['sounds']
        audio['types'][raw]=label
    audio_path.write_text(json.dumps(audio,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'assets/scenery/generated-ice.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'research/generated-ice-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print({key:row['clips'] for key,row in catalog.items()})

if __name__=='__main__':main()
