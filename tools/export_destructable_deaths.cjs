// Original Death vertex/normal tracks sampled at 30 Hz for GPU-instanced scenery.
const fs=require('fs'),path=require('path'),w=require('war3-model'),{vec3,mat3}=require('gl-matrix');
const root=path.resolve(__dirname,'..'),out=path.join(root,'assets/scenery/deaths');fs.mkdirSync(out,{recursive:true});
const source=JSON.parse(fs.readFileSync(path.join(root,'research/destructable-death-source.json'),'utf8'));
const result={models:{},types:source.types,native_placements:source.native_placements,field_zones:source.field_zones,initial_playable_bounds:source.initial_playable_bounds,tree_unit_art:source.tree_unit_art,note:source.note};
const clean=(_,v)=>ArrayBuffer.isView(v)?Array.from(v):v;
let totalBytes=0;
for(const entry of source.models){
 const b=fs.readFileSync(path.join(root,entry.source)),m=w.parseMDX(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));
 const sequence=m.Sequences.findIndex(s=>/^death$/i.test(s.Name));
 if(sequence<0){result.models[entry.id]={status:'no_death_sequence',source:entry.member};continue;}
 if(m.GlobalSequences.length)throw Error('Global tracks require live final-pose handling: '+entry.id);
 if(m.ParticleEmitters.length||m.ParticleEmitters2.length||m.RibbonEmitters.length||m.EventObjects.length||m.Lights.length)throw Error('Death component needs explicit integration: '+entry.id);
 if(m.Nodes.some(n=>n&&(n.Flags&255)))throw Error('Camera/inheritance flags require explicit death support: '+entry.id);
 const r=new w.ModelRenderer(m);r.setSequence(sequence);
 const interval=Array.from(m.Sequences[sequence].Interval),duration=(interval[1]-interval[0])/1000,frames=Math.ceil(duration*30)+1;
 const row={status:'death',source:entry.member,interval,duration,frames,meshes:[]};
 for(let gi=0;gi<m.Geosets.length;gi++){
  const g=m.Geosets[gi],layers=m.Materials[g.MaterialID].Layers;
  if(layers.length!==1)throw Error('Multi-layer death requires explicit export: '+entry.id);
  const layer=layers[0];if(typeof layer.TextureID!=='number'||layer.TVertexAnimId!=null)throw Error('Animated death texture needs explicit export: '+entry.id);
  const t=m.Textures[layer.TextureID];let texture=t.Image||'';
  if(t.ReplaceableId===entry.replacement_id&&entry.replacement)texture=entry.replacement;
  if(!texture)throw Error('Unresolved death texture: '+entry.id);
  const count=g.Vertices.length/3,positions=[],normals=[],alphas=[],colors=[];
  const low=[Infinity,Infinity,Infinity],high=[-Infinity,-Infinity,-Infinity];
  for(let frame=0;frame<frames;frame++){
   const time=Math.min(duration*1000,frame*1000/30);r.setFrame(interval[0]+time);r.rendererData.globalSequencesFrames=m.GlobalSequences.map(p=>time%p);r.updateNode(r.rendererData.rootNode);
   alphas.push(r.findAlpha(gi)*r.interp.animVectorVal(layer.Alpha,1));
   let tint=entry.tint;const animation=r.rendererData.geosetAnims[gi];
   if(animation&&(animation.Flags&2)){
    const color=animation.Color instanceof Float32Array?animation.Color:r.interp.vec3(new Float32Array(3),animation.Color);
    if(color)tint=tint.map((v,i)=>v*color[2-i]);
   }
   colors.push(tint);
   for(let v=0;v<count;v++){
    const p=vec3.create(),n=vec3.create(),original=g.Vertices.subarray(v*3,v*3+3),normal=g.Normals.subarray(v*3,v*3+3),group=g.Groups[g.VertexGroup[v]];
    for(const id of group){
     const matrix=r.rendererData.nodes[id]?.matrix;
     if(matrix){vec3.add(p,p,vec3.transformMat4(vec3.create(),original,matrix));vec3.add(n,n,vec3.transformMat3(vec3.create(),normal,mat3.normalFromMat4(mat3.create(),matrix)));}
     else{vec3.add(p,p,original);vec3.add(n,n,normal);}
    }
    if(group.length)vec3.scale(p,p,1/group.length);else{vec3.copy(p,original);vec3.copy(n,normal);}vec3.normalize(n,n);
    const point=[p[0]/100,p[2]/100,-p[1]/100];
    for(let axis=0;axis<3;axis++){low[axis]=Math.min(low[axis],point[axis]);high[axis]=Math.max(high[axis],point[axis]);}
    positions.push(...point,1);normals.push(n[0],n[2],-n[1],0);
   }
  }
  const prefix=entry.id+'-'+gi,indices=[];
  for(let i=0;i<g.Faces.length;i+=3)indices.push(g.Faces[i],g.Faces[i+2],g.Faces[i+1]);
  for(const [suffix,values] of [['positions',positions],['normals',normals]]){
   const bytes=Buffer.from(new Float32Array(values).buffer);fs.writeFileSync(path.join(out,prefix+'-'+suffix+'.deathanim'),bytes);totalBytes+=bytes.length;
  }
  row.meshes.push({vertices:positions.slice(0,count*4).filter((_,i)=>i%4!==3),normals:normals.slice(0,count*4).filter((_,i)=>i%4!==3),uv:Array.from(g.TVertices[0]),indices,
   vertex_count:count,texture,filter:layer.FilterMode,shading:layer.Shading,alphas,colors,
   positions:'res://assets/scenery/deaths/'+prefix+'-positions.deathanim',normal_frames:'res://assets/scenery/deaths/'+prefix+'-normals.deathanim',bounds:[low,high]});
 }
 result.models[entry.id]=row;
}
fs.writeFileSync(path.join(out,'catalog.json'),JSON.stringify(result,clean));
console.log('Death variants',Object.values(result.models).filter(x=>x.status==='death').length,'no Death',Object.entries(result.models).filter(([k,x])=>x.status!=='death').map(([k])=>k),'vertex bytes',totalBytes);
