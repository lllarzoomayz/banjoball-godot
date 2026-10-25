// Bake one original Stand pose per scenery variant; share it with MultiMesh.
// Asset geometry remains the user's local MDX, decoded by war3-model.
const fs=require('fs'),path=require('path'),w=require('war3-model');
const {vec3,mat3}=require('gl-matrix');
const root=path.resolve(__dirname,'..');
const source=JSON.parse(fs.readFileSync(path.join(root,'research/scenery-source.json'),'utf8'));
const output=path.join(root,'assets/scenery');fs.mkdirSync(output,{recursive:true});
const textures=new Set(),report=[];
const clean=(_,v)=>ArrayBuffer.isView(v)?Array.from(v):v;
const convert=(v,scale=1)=>[v[0]*scale,v[2]*scale,-v[1]*scale];
for(const entry of source.models){
 if(/\\LOSBlocker\\/i.test(entry.member)){
  report.push({id:entry.id,skip:'Editor pathing helper; invisible in game',meshes:0});continue;
 }
 const b=fs.readFileSync(path.join(root,entry.source));
 const model=w.parseMDX(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));
 const renderer=new w.ModelRenderer(model);
 const stand=Math.max(0,model.Sequences.findIndex(s=>/^stand/i.test(s.Name)));
 if(model.Sequences.length){renderer.setSequence(stand);renderer.setFrame(model.Sequences[stand].Interval[0]);}
 renderer.updateNode(renderer.rendererData.rootNode);
 const meshes=[];
 for(let gi=0;gi<model.Geosets.length;gi++){
  const g=model.Geosets[gi],alpha=renderer.findAlpha(gi);
  if(alpha<0.01)continue;
  const layers=model.Materials[g.MaterialID].Layers;
  let layer=layers[0],tex=model.Textures[typeof layer.TextureID==='number'?layer.TextureID:0];
  for(const l of layers){
   const t=model.Textures[typeof l.TextureID==='number'?l.TextureID:0];
   if(t?.Image||t?.ReplaceableId===entry.replacement_id){layer=l;tex=t;}
  }
  let texture=tex?.Image||'';
  if(tex?.ReplaceableId===entry.replacement_id&&entry.replacement)texture=entry.replacement;
  if(tex?.ReplaceableId===2)texture='ReplaceableTextures\\TeamGlow\\TeamGlow00.blp';
  if(texture)textures.add(texture);
  const opacity=alpha*renderer.interp.animVectorVal(layer.Alpha,1);
  if(opacity<0.01)continue;
  let tint=entry.tint;
  const anim=renderer.rendererData.geosetAnims[gi];
  if(anim&&(anim.Flags&2)){
   const c=anim.Color instanceof Float32Array?anim.Color:renderer.interp.vec3(new Float32Array(3),anim.Color);
   if(c)tint=tint.map((v,i)=>v*c[2-i]);
  }
  const vertices=[],normals=[],indices=[],uv=Array.from(g.TVertices[0]);
  for(let i=0;i<g.Vertices.length/3;i++){
   const p=vec3.create(),n=vec3.create();
   const original=g.Vertices.subarray(i*3,i*3+3),normal=g.Normals.subarray(i*3,i*3+3);
   const group=g.Groups[g.VertexGroup[i]];
   for(const id of group){
    const matrix=renderer.rendererData.nodes[id]?.matrix;
    if(matrix){
     vec3.add(p,p,vec3.transformMat4(vec3.create(),original,matrix));
     const m=mat3.normalFromMat4(mat3.create(),matrix);
     vec3.add(n,n,vec3.transformMat3(vec3.create(),normal,m));
    }else{vec3.add(p,p,original);vec3.add(n,n,normal);}
   }
   if(group.length)vec3.scale(p,p,1/group.length);else{vec3.copy(p,original);vec3.copy(n,normal);}
   vec3.normalize(n,n);
   vertices.push(...convert(p,.01));normals.push(...convert(n));
  }
  for(let i=0;i<g.Faces.length;i+=3)indices.push(g.Faces[i],g.Faces[i+2],g.Faces[i+1]);
  meshes.push({vertices,normals,uv,indices,texture,tint,opacity,filter:layer.FilterMode,shading:layer.Shading});
 }
 fs.writeFileSync(path.join(output,entry.id+'.json'),JSON.stringify({id:entry.id,meshes},clean));
 report.push({id:entry.id,meshes:meshes.length,vertices:meshes.reduce((n,g)=>n+g.vertices.length/3,0),
  particles:model.ParticleEmitters.length+model.ParticleEmitters2.length,ribbons:model.RibbonEmitters.length,
  texture_animations:model.TextureAnims.length,pose:model.Sequences[stand]?.Name||'bind'});
}
fs.writeFileSync(path.join(root,'research/scenery-conversion.json'),JSON.stringify({models:report,textures:[...textures]},null,2));
console.log('Baked scenery variants:',report.length,'meshes:',report.reduce((n,r)=>n+r.meshes,0),'textures:',textures.size);
