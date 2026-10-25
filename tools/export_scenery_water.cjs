const fs=require('fs'),w=require('war3-model');
const source=JSON.parse(fs.readFileSync('research/scenery-source.json','utf8')),e=source.models.find(x=>x.id==='B000_0');
const b=fs.readFileSync(e.source),m=w.parseMDX(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));
if(m.Geosets.length!==2||m.Nodes.length!==1||m.Nodes[0].Translation||m.Nodes[0].Rotation||m.Nodes[0].Scaling)throw new Error('Water requires static mesh verification');
const data={member:e.member,interval:[...m.Sequences[0].Interval],periods:m.GlobalSequences,textures:m.Textures,meshes:m.Geosets.map(g=>({layers:m.Materials[g.MaterialID].Layers}))};
fs.writeFileSync('assets/scenery/animated_materials.json',JSON.stringify({B000_0:data},(_,v)=>ArrayBuffer.isView(v)?Array.from(v):v,2));
