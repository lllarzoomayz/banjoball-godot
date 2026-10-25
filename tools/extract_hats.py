"""Original Pick__hats, map-first archives; no substitute artwork."""
import json,re,subprocess
from extract_assets import ROOT,extract,convert_textures,manifest

script=(ROOT/'research/war3map.j').read_text(encoding='utf-8')
units=json.loads((ROOT/'research/map-units.json').read_text(encoding='utf-8'))
source_names={int(u['fields']['upoi']):u['fields']['unam'] for u in units if u['fields'].get('umdl')=='.mdl' and 'upoi' in u['fields']}
labels=['厨师帽','软呢帽','军帽','海盗帽','圣诞帽','猎巫帽','十字军头盔','南瓜头','武士头盔','斯巴达头盔','巫毒面具','萨满狼帽','不戴帽子','企鹅','小鸡','绵羊','青蛙','兔子','小猪','浣熊','雄鹿','猫头鹰','狼','螃蟹','海豹','不戴帽子','牛仔帽','王冠','大地术士帽','交通锥','钓鱼帽','光环','米老鼠耳朵','问号','草帽','火枪手帽','头巾','队色巫师帽']
rows=[];models=[];textures=[]
for index,member in re.findall(r'set Pick__hats\[(\d+)\]="([^"]*)"',script):
    index=int(index);member=member.replace('\\\\','\\');model='hat_'+str(index).zfill(2) if member else ''
    row={'index':index,'name':labels[index],'source_name':source_names.get(index,''),'source_member':member,'model':model}
    if member:
        path=extract(member)
        if path is None or not path.stat().st_size:raise FileNotFoundError(member)
        models.append(dict(id=model,name=labels[index],model_file=str(path.relative_to(ROOT)),model_member=member,scale=1,animation='',prop=True,effect=True,cosmetic=True))
    rows.append(row)
(ROOT/'research/cosmetic-assets.json').write_text(json.dumps(models,ensure_ascii=False,indent=2),encoding='utf-8')
events=[];unsupported=[]
for a in models:
    subprocess.run(['node',str(ROOT/'tools/convert_models.cjs'),'--only',a['id']],check=True,cwd=ROOT)
    d=json.loads((ROOT/'assets/models'/f"{a['id']}.json").read_text(encoding='utf-8'))
    for clip in d['clips']:
        for e in clip.get('events',[]):events.append(dict(model=a['id'],clip=clip['name'],event=e))
    for t in d['textures']:
        if not t.get('Image'):continue
        p=extract(t['Image'])
        if p is None or not p.stat().st_size:raise FileNotFoundError(t['Image'])
        textures.append(p)
convert_textures(textures)
folder=ROOT/'assets/models/cosmetics';folder.mkdir(exist_ok=True)
(folder/'hats.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'research/hat-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'research/hat-event-dependencies.json').write_text(json.dumps(events,ensure_ascii=False,indent=2),encoding='utf-8')
print('Original hats',len(models),'unique textures',len(set(textures)),'clip event keys',len(events))
