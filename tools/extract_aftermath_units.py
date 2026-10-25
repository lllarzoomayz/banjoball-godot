"""Resolve original nske/nska data and arrow art from the local Warcraft install."""
import json, re, subprocess
from extract_assets import ROOT, extract, convert_textures, manifest
from extract_scenery import slk

def main():
    tables={name:slk(extract('Units\\'+name+'.slk')) for name in ['UnitData','UnitBalance','UnitWeapons','UnitUI','UnitAbilities']}
    func=extract(r'Units\NeutralUnitFunc.txt').read_text('utf-8',errors='replace')
    misc=extract(r'Units\MiscGame.txt').read_text('utf-8',errors='replace')
    result={'units':{},'armor_factor':float(re.search(r'^DefenseArmor=(.+)$',misc,re.M)[1]),'notes':['Map modifies only food/name for nske/nska; no combat-stat changes.','Both armor classes are large; Normal and Pierce coefficients against large are 1.0 in local MiscGame.','Native path scheduler, launch arc and exact contact range need independent calibration; source values are retained.']}
    textures=[]
    for raw in ['nske','nska']:
        d,b,w,ui,abil=[tables[name][raw] for name in tables]
        body=re.search(r'^\['+raw+r'\]\s*\n(.*?)(?=^\[|\Z)',func,re.S|re.M)[1]
        values=dict(re.findall(r'(?m)^(\w+)=(.*)$',body))
        portrait=extract(values['Art'].strip());textures.append(portrait)
        result['units'][raw]={'model':'apoc_skeleton' if raw=='nske' else 'apoc_skeleton_archer','name':'骷髅战士' if raw=='nske' else '骷髅弓箭手','hp':b['HP'],'armor':b['def'],'armor_type':b['defType'],'speed':b['spd'],'radius':b['collision'],'turn':d['turnRate'],'prop_window':d['propWin'],'death':d['death'],'regen':b['regenHP'],'regen_type':b['regenType'],'range':w['rangeN1'],'range_buffer':w['RngBuff1'],'acquire':w['acquire'],'cooldown':w['cool1'],'attack_point':w['dmgpt1'],'backswing':w['backSw1'],'damage_base':w['dmgplus1'],'damage_dice':w['dice1'],'damage_sides':w['sides1'],'attack_type':w['atkType1'],'missile':w['weapTp1']=='missile','missile_speed':float(values.get('Missilespeed',0)),'missile_arc':float(values.get('Missilearc',0)),'launch':[w['launchX'],w['launchY'],w['launchZ']],'impact':w['impactZ'],'walk_animation_speed':ui['walk'],'portrait':'res://assets/textures/'+portrait.name+'.png','source':{name:tables[name][raw] for name in tables}}
    member=r'Abilities\Weapons\Arrow\ArrowMissile.mdx';source=extract(member)
    props_path=ROOT/'research/props.json';props=json.loads(props_path.read_text('utf-8'))
    props=[x for x in props if x['id']!='apoc_arrow']
    props.append({'id':'apoc_arrow','name':'Skeleton Archer arrow','model_file':str(source.relative_to(ROOT)),'model_member':member,'scale':1,'animation':'','prop':True,'apocalypse':True})
    props_path.write_text(json.dumps(props,ensure_ascii=False,indent=2),encoding='utf-8')
    subprocess.run(['node',str(ROOT/'tools/convert_models.cjs'),'--only','apoc_arrow'],cwd=ROOT,check=True)
    model=json.loads((ROOT/'assets/models/apoc_arrow.json').read_text('utf-8'))
    for row in model['textures']:
        if row['Image']:textures.append(extract(row['Image']))
    convert_textures(textures)
    (ROOT/'assets/scenery/aftermath-units.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'research/aftermath-unit-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Resolved two original combat units and original arrow/portraits.')

if __name__=='__main__':main()
