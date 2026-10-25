"""Restore original W3E seabed outside the frozen fields' existing terrain crop.

Use the same native tile/mask composition as bake_field_terrain, at 32 texels
per cell for this distant underwater ring. No geometry/terrain is invented.
"""
import json,math
from PIL import Image
from extract_assets import ROOT,safe_name
from extract_scenery import terrain

def main():
    land=terrain();nx,ny=land['size'];ox,oy=land['origin']
    source=json.loads((ROOT/'research/scenery-source.json').read_text(encoding='utf-8'))
    world=json.loads((ROOT/'assets/scenery/apocalypse-world.json').read_text())
    fields=json.loads((ROOT/'research/fields.json').read_text(encoding='utf-8'))['fields']
    atlases=[Image.open(ROOT/'assets/textures'/(safe_name(t['member'])+'.png')).convert('RGBA') for t in source['fields'][0]['tile_assets']]
    tiles={}
    def tile(texture,cell):
        key=(texture,cell)
        if key not in tiles:
            atlas=atlases[texture];size=atlas.height//4;x=cell%4+(4 if cell>=16 else 0);y=(cell%16)//4
            tiles[key]=atlas.crop((x*size,y*size,(x+1)*size,(y+1)*size)).resize((32,32),Image.Resampling.BILINEAR)
        return tiles[key]
    reports=[]
    for index in [2,3]:
        f=fields[index];cx,cy=f['center'];zone=world['fields'][index]['zone'];old=json.loads((ROOT/'assets/scenery'/f"{f['id']}.json").read_text())
        x0=max(0,math.floor((zone[0]-2048-ox)/128));x1=min(nx-1,math.ceil((zone[2]+2048-ox)/128))
        y0=max(0,math.floor((zone[1]-2048-oy)/128));y1=min(ny-1,math.ceil((zone[3]+2048-oy)/128))
        width=x1-x0+1;height=y1-y0+1
        corners=[land['corners'][y*nx+x] for y in range(y0,y1+1) for x in range(x0,x1+1)]
        image=Image.new('RGB',((width-1)*32,(height-1)*32))
        for y in range(height-1):
            for x in range(width-1):
                c=[corners[y*width+x],corners[y*width+x+1],corners[(y+1)*width+x],corners[(y+1)*width+x+1]]
                textures=sorted({v['ground'] for v in c});base=textures[0];variation=c[0]['variation']
                cell=(variation+16 if variation<16 else (15 if variation==16 else 0)) if atlases[base].width>atlases[base].height else (0 if variation==0 else 15)
                result=tile(base,cell).convert('RGB')
                for texture in textures[1:]:
                    mask=sum(bit for v,bit in zip(c,[2,1,8,4]) if v['ground']==texture);overlay=tile(texture,mask);result.paste(overlay,(0,0),overlay.getchannel('A'))
                image.paste(result,(x*32,(height-2-y)*32))
        name=f['id']+'_seabed';image.save(ROOT/'assets/scenery'/f'{name}.png')
        data=dict(id=name,bounds=[ox+x0*128-cx,oy+y0*128-cy,ox+x1*128-cx,oy+y1*128-cy],grid=[width,height],heights=[c['height']-f['world_height_offset'] for c in corners],texture=f'res://assets/scenery/{name}.png',skip_bounds=old['bounds'])
        (ROOT/'assets/scenery'/f'{name}.json').write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
        reports.append(dict(field=f['id'],bounds=data['bounds'],skip_bounds=data['skip_bounds'],grid=data['grid'],texture_size=image.size))
    (ROOT/'research/generated-ice-backdrop.json').write_text(json.dumps(reports,indent=2));print(reports)

if __name__=='__main__':main()
