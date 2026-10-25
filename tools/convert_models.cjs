// Parse classic MDX with the MIT-licensed war3-model library. Bake existing
// node animation matrices for Godot; no game geometry or animation is invented.
const fs=require('fs'),path=require('path'),w=require('war3-model');
const root=path.resolve(__dirname,'..');
const {rawEvents,clipEvents}=require('./mdx_events.cjs');
const actors=JSON.parse(fs.readFileSync(path.join(root,'research/actors.json'),'utf8'));
const propsPath=path.join(root,'research/props.json');
if(fs.existsSync(propsPath))actors.push(...JSON.parse(fs.readFileSync(propsPath,'utf8')));
const effectsPath=path.join(root,'research/spell-assets.json');
if(fs.existsSync(effectsPath))actors.push(...JSON.parse(fs.readFileSync(effectsPath,'utf8')));
const spawnedPath=path.join(root,'research/event-spawn-assets.json');
if(fs.existsSync(spawnedPath))actors.push(...JSON.parse(fs.readFileSync(spawnedPath,'utf8')));
const cosmeticsPath=path.join(root,'research/cosmetic-assets.json');
if(fs.existsSync(cosmeticsPath))actors.push(...JSON.parse(fs.readFileSync(cosmeticsPath,'utf8')));
const clean=x=>ArrayBuffer.isView(x)?Array.from(x):x;
const identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
const report=[];
for(const actor of actors){
 if(process.argv.includes('--only') && actor.id!==process.argv[process.argv.indexOf('--only')+1])continue;
 if(!actor.model_file) continue;
 const b=fs.readFileSync(path.join(root,actor.model_file));
 const model=w.parseMDX(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));
 // An original static attachment can omit SEQS entirely. Give the baker a
 // constant pose interval; no animated node tracks may be invented here.
 if(!model.Sequences.length){
  if(model.Nodes.some(n=>n&&(n.Translation||n.Rotation||n.Scaling))||model.GlobalSequences.length)throw new Error('Sequence-less animated model needs explicit handling: '+actor.id);
  model.Sequences.push({Name:'Stand',Interval:new Uint32Array([0,1000]),NonLooping:0});
 }
 const renderer=new w.ModelRenderer(model);
 const events=rawEvents(b);
 const billboardNodes=model.Nodes.filter(n=>n&&(n.Flags&8));
 const needed=[...new Set([...model.Geosets.flatMap(g=>g.Groups.flat()),...model.ParticleEmitters2.map(e=>e.ObjectId),...model.RibbonEmitters.map(e=>e.ObjectId),...billboardNodes.map(n=>n.ObjectId),...model.Attachments.map(n=>n.ObjectId)])].sort((a,b)=>a-b);
 if(!needed.length)needed.push(0);
 const idToIndex=new Map(needed.map((x,i)=>[x,i]));
 const meshes=model.Geosets.map(g=>({vertices:g.Vertices,normals:g.Normals,uv:g.TVertices[0],faces:g.Faces,
   groups:g.Groups.map(gr=>gr.map(id=>idToIndex.get(id))),vertex_group:g.VertexGroup,material:g.MaterialID}));
 let selected=[];
 for(const term of (actor.cosmetic?['Stand','Birth','Death']:['Stand','Walk','Attack','Attack Slam','Spell','Death',...(actor.prop?['Birth']:[])])){
  let idx=actor.animation ? model.Sequences.findIndex(s=>s.Name.toLowerCase().startsWith(term.toLowerCase())&&s.Name.toLowerCase().includes(actor.animation.toLowerCase())) : -1;
  if(idx<0)idx=model.Sequences.findIndex(s=>s.Name.toLowerCase().startsWith(term.toLowerCase())&&!/alternate|swim|channel|ready/i.test(s.Name));
  if(idx<0)idx=model.Sequences.findIndex(s=>s.Name.toLowerCase().startsWith(term.toLowerCase()));
  if(idx>=0&&!selected.includes(idx))selected.push(idx);
 }
 if(!selected.length)selected=[0];
 // Retain every original cosmetic lifecycle clip. Runtime eligibility remains
 // separate from storage: Swim/Ready/Fourth must not become random Stand.
 if(actor.cosmetic){
  model.Sequences.forEach((s,i)=>{if(/^(stand|birth|death)(?:\s|$)/i.test(s.Name)&&!selected.includes(i))selected.push(i);});
 }
 // Backflip uses sequence index 2 on the same original ninja model.
 if(actor.id==='h00R'&&!selected.includes(2))selected.push(2);
 if(actor.id==='h012'&&!selected.includes(5))selected.push(5);
 if(actor.id==='h029'&&!selected.includes(8))selected.push(8);
 // Smash explicitly plays original MDX sequence 6: Attack 2, not Spell.
 if(actor.id==='h026'&&!selected.includes(6))selected.push(6);
 // SPN plays source sequence zero once, independently of its name.
 if(actor.event_spawn)selected=[0];
 const numbers=[],clips=[];
 for(const idx of selected){
  renderer.setSequence(idx);
  const seq=model.Sequences[idx],duration=(seq.Interval[1]-seq.Interval[0])/1000;
  const frames=Math.max(2,Math.ceil(duration*30)+1),offset=numbers.length,alphas=[],layer_alphas=[],layer_textures=[],colors=[],emitters=[],ribbons=[],light_positions=[],light_visible=[];
  for(let f=0;f<frames;f++){
   const ms=seq.Interval[0]+Math.min(duration*1000,f*1000/30);
   renderer.setFrame(ms);
   renderer.rendererData.globalSequencesFrames=model.GlobalSequences.map(n=>(ms-seq.Interval[0])%n);
   renderer.updateNode(renderer.rendererData.rootNode);
   light_positions.push(model.Lights.map(l=>{
    const m=renderer.rendererData.nodes[l.ObjectId].matrix,p=l.PivotPoint;
    return [0,1,2].map(i=>m[i]*p[0]+m[4+i]*p[1]+m[8+i]*p[2]+m[12+i]);
   }));
   light_visible.push(model.Lights.map(l=>renderer.interp.animVectorVal(l.Visibility,1)>0 &&
    (renderer.interp.animVectorVal(l.Intensity,0)>0 || renderer.interp.animVectorVal(l.AmbIntensity,0)>0)));
   for(const id of needed){
    const m=renderer.rendererData.nodes[id]?.matrix||identity;
    // Full 4x4 column-major native coordinates. Conversion happens in Godot.
    numbers.push(...m);
   }
   alphas.push(model.Geosets.map((_,i)=>renderer.findAlpha(i)));
   colors.push(model.Geosets.map((_,i)=>{
    const a=renderer.rendererData.geosetAnims[i];
    if(!a || !(a.Flags&2))return [1,1,1];
    const color=a.Color instanceof Float32Array ? a.Color : renderer.interp.vec3(new Float32Array(3),a.Color);
    // war3-model exposes MDX colors in RGB (its MDL parser reverses text BGR).
    // Reversing here again turned the source blue goal flash orange.
    return color ? Array.from(color) : [1,1,1];
   }));
   layer_alphas.push(model.Materials.map(m=>m.Layers.map(l=>renderer.interp.animVectorVal(l.Alpha,1))));
   layer_textures.push(model.Materials.map(m=>m.Layers.map(l=>renderer.interp.animVectorVal(l.TextureID,0))));
   emitters.push(model.ParticleEmitters2.map(e=>{
    const values=['Visibility','Speed','Variation','Latitude','Gravity','EmissionRate','Width','Length'].map(k=>renderer.interp.animVectorVal(e[k],k==='Visibility'?1:0));
    const key=e.Squirt&&typeof e.EmissionRate!=='number'?renderer.interp.findKeyframes(e.EmissionRate)?.left:null;
    values.push(key?key.Frame:-1,key?key.Vector[0]:0);return values;
   }));
   ribbons.push(model.RibbonEmitters.map(e=>['Visibility','HeightAbove','HeightBelow','Alpha','TextureSlot'].map(k=>renderer.interp.animVectorVal(e[k],k==='Visibility'||k==='Alpha'?1:0))));
  }
  clips.push({name:seq.Name,source_index:idx,rarity:seq.Rarity,source_non_looping:!!seq.NonLooping,interval:seq.Interval,duration,frames,offset,alphas,layer_alphas,layer_textures,colors,emitters,ribbons,light_positions,light_visible,events:clipEvents(model,renderer,events,seq),loop:actor.cosmetic?!seq.NonLooping:!/death|attack|spell|birth/i.test(seq.Name)&&!(actor.id==='h00R'&&idx===2)});
 }
 const out={actor,meshes,bone_ids:needed,clips,textures:model.Textures,materials:model.Materials,lights:model.Lights,
   texture_animations:model.TextureAnims,global_sequences:model.GlobalSequences,
   attachments:model.Attachments.map(a=>({name:a.Name,bone_index:idToIndex.get(a.ObjectId),pivot:a.PivotPoint})),
   emitters:model.ParticleEmitters2.map(e=>({...e,bone_index:idToIndex.get(e.ObjectId)})),
   ribbons:model.RibbonEmitters.map(e=>({...e,bone_index:idToIndex.get(e.ObjectId)})),
   billboards:billboardNodes.map(node=>({bone_index:idToIndex.get(node.ObjectId),pivot:node.PivotPoint,
    affected:needed.filter(id=>{let n=model.Nodes[id];while(n){if(n.ObjectId===node.ObjectId)return true;n=n.Parent===null?null:model.Nodes[n.Parent];}return false;}).map(id=>idToIndex.get(id))})),
   limitations:{particle_emitters:model.ParticleEmitters.length+model.ParticleEmitters2.length,ribbons:model.RibbonEmitters.length,texture_animations:model.TextureAnims.length},
   bounds:{min:model.Info.MinimumExtent,max:model.Info.MaximumExtent}};
 require('./model_visibility.cjs')(out);
 // Scenery can have independent bone clocks longer/shorter than Stand. Keep
 // their original tracks rather than resetting them at the baked clip loop.
 if(actor.scenery && model.Nodes.some(n=>n&&((n.Flags&120)||['Translation','Rotation','Scaling'].some(k=>n[k]?.GlobalSeqId!=null&&model.GlobalSequences[n[k].GlobalSeqId]>0)))){
  if(model.Nodes.some(n=>n&&(n.Flags&135)))throw new Error('Live scenery pose needs explicit inheritance/camera-anchor support');
  out.live_pose_camera=model.Nodes.some(n=>n&&(n.Flags&120));
  const pending=model.Nodes.filter(Boolean).map(n=>({id:n.ObjectId,parent:n.Parent,flags:n.Flags,pivot:n.PivotPoint,translation:n.Translation,rotation:n.Rotation,scaling:n.Scaling}));
  out.live_pose_nodes=[];const done=new Set();
  while(pending.length){const index=pending.findIndex(n=>n.parent==null||done.has(n.parent));if(index<0)throw new Error('Cyclic source node hierarchy');const [n]=pending.splice(index,1);out.live_pose_nodes.push(n);done.add(n.id);}
 }
 fs.writeFileSync(path.join(root,'assets/models',actor.id+'.json'),JSON.stringify(out,(_,v)=>clean(v)));
 const floats=new Float32Array(numbers);
 fs.writeFileSync(path.join(root,'assets/models',actor.id+'.wc3anim'),Buffer.from(floats.buffer));
 report.push({id:actor.id,name:actor.name,geosets:meshes.length,bones:needed.length,max_group:Math.max(...meshes.flatMap(m=>m.groups.map(g=>g.length))),animations:clips.map(x=>x.name),bytes:floats.byteLength,limitations:out.limitations});
 console.log(actor.id,actor.name,meshes.length,'meshes',needed.length,'bones',floats.byteLength,'animation bytes');
}
const reportName=process.argv.includes('--only')?'model-conversion-'+process.argv[process.argv.indexOf('--only')+1]+'.json':'model-conversion.json';
fs.writeFileSync(path.join(root,'research',reportName),JSON.stringify(report,null,2));
