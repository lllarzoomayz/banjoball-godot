"""Derive every original field's relocated rectangles and WPM occupancy.

No executable map code is run. Source rectangles and the explicit relocation
table in Fields__setupRegions are parsed, then centered for Godot's simulation.
"""
import hashlib,json,pathlib,re,struct,collections,math
ROOT=pathlib.Path(__file__).resolve().parents[1]
raw=(ROOT/'research/war3map.j').read_bytes()
try:j=raw.decode('utf8')
except UnicodeDecodeError:j=raw.decode('gb18030')
regions={n:[float(x) for x in v.split(',')] for n,v in re.findall(r'set gg_rct_(\w+)=Rect\(([^)]+)\)',j)}
fields=re.findall(r'set field=s__Field_create\((.+?),([-\d.]+),([-\d.]+),(\d+),(\d+),gg_rct_(\w+),',j)
assert len(fields)==4,fields
base_center=[float(fields[0][1]),float(fields[0][2])]
base_width,base_height=map(int,fields[0][3:5])
setup=j.split('function Fields__setupRegions')[1].split('endfunction')[0]
moves={n:[int(x) for x in v.split(',')] for n,v in re.findall(r's__Fields__Rectangle_create\(gg_rct_(\w+),([\d,\-]+)\)',setup)}
boundary_setup=j.split('function Boundary__setupBounds')[1].split('endfunction')[0]
boundary_names=re.findall(r'RegionAddRect\(Boundary__bounds\[(\d+)\],gg_rct_(\w+)\)',boundary_setup)
boundary_angles={n:int(re.search(r'GetHandleId\(Boundary__bounds\['+i+r'\]\),(\d+)\)',boundary_setup)[1]) for i,n in boundary_names}
w=(ROOT/'research/war3map.wpm').read_bytes();_,_,nx,ny=struct.unpack_from('<4sIII',w)
e=(ROOT/'research/war3map.w3e').read_bytes();offset=13
for _ in range(2):
 n,=struct.unpack_from('<I',e,offset);offset+=4+n*4
terrain_nx,terrain_ny,ox,oy=struct.unpack_from('<IIff',e,offset)
terrain_start=offset+16
assert len(e)-terrain_start==terrain_nx*terrain_ny*7
def terrain_height(x,y):
 ground,water,flags,variation,cliff=struct.unpack_from('<hhBBB',e,terrain_start+(y*terrain_nx+x)*7)
 return (ground-8192)/4+((cliff&15)-2)*128
catalog=[]
required=['Field','Goal_1','Goal_2','Goal_1_Area','Goal_2_Area','Goal_1_Front','Goal_2_Front','Start_1','Start_2']
for title,cx,cy,bw,bh,zone in fields:
 center=[float(cx),float(cy)];dx=(int(bw)-base_width)*64;dy=(int(bh)-base_height)*64
 shifted={}
 for name,coords in regions.items():
  move=moves.get(name,[0,0,0,0,0,0])
  shifted[name]=[v-base_center[k%2]+(move[k%2]+move[k+2])*(dx if k%2==0 else dy) for k,v in enumerate(coords)]
 # These face markers are not in the original relocation table. Reconstruct
 # them next to each relocated goal rather than leaving them on another field.
 for side in [1,2]:
  name=f'Goal_{side}_Front_Face'
  shifted[name]=[v-base_center[k%2]+((-dx if side==1 else dx) if k%2==0 else 0) for k,v in enumerate(regions[name])]
 playable=[shifted[n] for n in ['Field','Goal_1_Area','Goal_2_Area']]
 # Keep the original absolute altitude even though the renderer/simulation
 # use a pitch-local zero. Object_iterate32 has an ABSOLUTE z>=1 branch.
 tx,ty=(center[0]-ox)/128,(center[1]-oy)/128
 center_heights={terrain_height(x,y) for y in {math.floor(ty),math.ceil(ty)} for x in {math.floor(tx),math.ceil(tx)}}
 assert len(center_heights)==1, 'Center is not flat; explicit terrain interpolation required'
 base_z=center_heights.pop()
 heights=[]
 for r in playable:
  for y in range(max(0,math.floor((center[1]+r[1]-oy)/128)),min(terrain_ny-1,math.ceil((center[1]+r[3]-oy)/128))+1):
   for x in range(max(0,math.floor((center[0]+r[0]-ox)/128)),min(terrain_nx-1,math.ceil((center[0]+r[2]-ox)/128))+1):
    heights.append(terrain_height(x,y))
 minx,miny=min(r[0] for r in playable),min(r[1] for r in playable)
 maxx,maxy=max(r[2] for r in playable),max(r[3] for r in playable)
 sample=playable+[shifted[n] for _,n in boundary_names]
 sample_bounds=[min(r[0] for r in sample),min(r[1] for r in sample),max(r[2] for r in sample),max(r[3] for r in sample)]
 counts=collections.Counter();blocked=[];stall_blocked=[]
 for y in range(max(0,int((sample_bounds[1]+center[1]-oy)//32)),min(ny,int((sample_bounds[3]+center[1]-oy)//32)+1)):
  for x in range(max(0,int((sample_bounds[0]+center[0]-ox)//32)),min(nx,int((sample_bounds[2]+center[0]-ox)//32)+1)):
   px,py=ox+x*32+16-center[0],oy+y*32+16-center[1]
   flags=w[16+y*nx+x]
   if flags&2:stall_blocked.append([px-16,py-16,px+16,py+16])
   if any(r[0]<=px<r[2] and r[1]<=py<r[3] for r in playable):
    counts[flags]+=1
    if flags&2:blocked.append([px-16,py-16,px+16,py+16])
 name=re.search(r'"\|c[\da-fA-F]{8}([^|]+)',title)[1]
 catalog.append(dict(id=zone,name=name,center=center,block_width=int(bw),block_height=int(bh),recommended_team=5 if int(bw)>32 else 4,
  theme='ice' if zone.startswith('Frozen') else 'grass',world_height_offset=base_z,terrain_height_range=[min(heights),max(heights)],regions={n:shifted[n] for n in required+['Goal_1_Front_Face','Goal_2_Front_Face']},
  boundaries=[dict(name=n,rect=shifted[n],normal_degrees=boundary_angles[n],min_height=300 if int(i)>=16 else 0,max_height=32468) for i,n in boundary_names],
  terrain_blocked=blocked,stall_blocked=stall_blocked,terrain_sample_bounds=sample_bounds,pathing_flag_counts=dict(counts)))
out=dict(source='弹跳足球_1.27兼容版 / Fields__setupRegions + WPM + W3E absolute elevation',script_sha256=hashlib.sha256(raw).hexdigest(),terrain_sha256=hashlib.sha256(e).hexdigest(),fields=catalog,
 caveat='Normalized local coordinates with original absolute pitch height offset. All playable corner heights exceed 1, validating the Object collision threshold despite unported local terrain interpolation. Original front-face marker relocation omission repaired. Native region rasterization remains separate work.')
(ROOT/'research/fields.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf8')
for f in catalog:print(f['name'],f['regions']['Field'],'blocked:',len(f['terrain_blocked']))
