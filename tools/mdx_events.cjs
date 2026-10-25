// Preserve KEVT's global sequence field (omitted by war3-model 4.0.1).
const assert=require('assert');
const {mat4,quat}=require('gl-matrix');
function rawEvents(b){
 const result=[];assert.equal(b.toString('ascii',0,4),'MDLX');
 for(let o=4;o<b.length;){
  const tag=b.toString('ascii',o,o+4),end=o+8+b.readUInt32LE(o+4);assert(end<=b.length);
  if(tag==='EVTS'){
   let p=o+8;
   while(p<end){
    const nodeSize=b.readUInt32LE(p);assert(nodeSize>=96&&p+nodeSize+12<=end);
    const name=b.toString('utf8',p+4,p+84).split('\0')[0],id=b.readUInt32LE(p+84);
    const k=p+nodeSize;assert.equal(b.toString('ascii',k,k+4),'KEVT');
    const count=b.readUInt32LE(k+4),globalSequence=b.readInt32LE(k+8);assert(k+12+count*4<=end);
    const frames=Array.from({length:count},(_,i)=>b.readUInt32LE(k+12+i*4));
    result.push({name,id,global_sequence:globalSequence,frames});p=k+12+count*4;
   }
   assert.equal(p,end);
  }
  o=end;
 }
 return result;
}
function clipEvents(model,renderer,raw,sequence){
 const events=[];
 for(const e of raw){
  // No global-sequence event exists in the current catalog. Fail explicitly
  // if new assets need that separate clock rather than silently misplay it.
  assert(e.global_sequence===-1,'Global-sequence EVTS requires its own clock: '+e.name);
  const node=model.EventObjects.find(n=>n.ObjectId===e.id);
  assert(node&&node.Name===e.name);assert.deepEqual(e.frames,Array.from(node.EventTrack));
  for(const frame of e.frames){
   if(frame<sequence.Interval[0]||frame>sequence.Interval[1])continue;
   renderer.setFrame(frame);
   renderer.rendererData.globalSequencesFrames=model.GlobalSequences.map(n=>(frame-sequence.Interval[0])%n);
   renderer.updateNode(renderer.rendererData.rootNode);
   const matrix=renderer.rendererData.nodes[e.id].matrix,p=node.PivotPoint;
   const position=[0,1,2].map(i=>matrix[i]*p[0]+matrix[4+i]*p[1]+matrix[8+i]*p[2]+matrix[12+i]);
   const rotation=quat.normalize(quat.create(),mat4.getRotation(quat.create(),matrix));
   const basis=[0,1,2,4,5,6,8,9,10].map(i=>matrix[i]);
   events.push({name:e.name,node:e.id,type:e.name.slice(0,3),code:e.name.slice(4,8),time:(frame-sequence.Interval[0])/1000,position,rotation:Array.from(rotation),basis});
  }
 }
 return events.sort((a,b)=>a.time-b.time||a.node-b.node);
}
module.exports={rawEvents,clipEvents};
