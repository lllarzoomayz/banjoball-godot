// Independent reference matrices from the upstream model renderer, not from
// Godot's track sampler. Only local owned MDX input is used.
const fs=require('fs'),path=require('path'),w=require('war3-model');
const root=path.resolve(__dirname,'..');
const actor=JSON.parse(fs.readFileSync(path.join(root,'assets/models/h012.json'),'utf8')).actor;
const b=fs.readFileSync(path.join(root,actor.model_file));
const model=w.parseMDX(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));
const renderer=new w.ModelRenderer(model),rows=[];
for(const si of [0,1,2]){
 renderer.setSequence(si);
 const seq=model.Sequences[si];
 for(const seconds of [0,.001,.033,.125,.249,.251,.499,.501,.875,1,1.375,2.01]){
  const frame=seq.Interval[0]+Math.min(100,seq.Interval[1]-seq.Interval[0]);
  renderer.setFrame(frame);
  renderer.rendererData.globalSequencesFrames=model.GlobalSequences.map(n=>seconds*1000%n);
  for(let i=0;i<model.TextureAnims.length;i++)rows.push({animation:i,frame,interval:Array.from(seq.Interval),seconds,matrix:Array.from(renderer.getTexCoordMatrix({TVertexAnimId:i}))});
 }
}
fs.writeFileSync(path.join(root,'research/uv-reference.json'),JSON.stringify({source:'war3-model 4.0.1 ModelRenderer.getTexCoordMatrix / local h012 MDX',rows},null,2));
console.log(rows.length,'independent UV reference matrices');
