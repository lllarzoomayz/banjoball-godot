// Conservative last frame that can show mesh geometry or emit new trails.
// Legacy models keep their established bounds. Layer-pass models use interval
// bounds: independent alpha tracks may overlap between zero-product endpoints.
function annotate(data) {
 for(const clip of data.clips) {
  let last=-1;
  for(let f=0;f<clip.frames;f++) {
   let active=clip.alphas[f].some((a,i)=>{
    if(!data.actor?.material_layer_passes || !clip.layer_alphas)return a>0;
    // Bound an entire interpolation interval, rather than multiplying only
    // endpoint values. A geoset fading out and a layer fading in can still
    // overlap even if both endpoint products are zero.
    const previous=Math.max(0,f-1),material=data.meshes[i].material;
    if(Math.max(a,clip.alphas[previous][i])<=0)return false;
    return clip.layer_alphas[f][material].some((alpha,j)=>Math.max(alpha,clip.layer_alphas[previous][material][j])>0);
   });
   for(let i=0;i<(data.emitters||[]).length;i++) {
    const v=clip.emitters[f][i],source=data.emitters[i];
    active ||= v[0]>0 && (source.Squirt && v[8]>=0 ? v[9]>0 : v[5]>0);
   }
   for(let i=0;i<(data.ribbons||[]).length;i++) {
    active ||= clip.ribbons[f][i][0]>0 && data.ribbons[i].EmissionRate>0;
   }
   active ||= (clip.light_visible?.[f]||[]).some(Boolean);
   if(active)last=f;
  }
  // Keep one complete sample interval for interpolation to zero.
  // A one-shot clamps to its last frame. If that frame still draws anything,
  // its final pose must remain until the caller's ordinary lifetime expires.
  clip.visual_end=last===clip.frames-1 ? clip.duration+1 : (last+1)/30;
 }
 return data;
}
module.exports=annotate;
if(require.main===module) {
 const fs=require('fs'),path=require('path');
 const root=path.resolve(__dirname,'../assets/models');let count=0;
 for(const name of fs.readdirSync(root))if(name.endsWith('.json')) {
  const file=path.join(root,name),data=JSON.parse(fs.readFileSync(file,'utf8'));
  annotate(data);fs.writeFileSync(file,JSON.stringify(data));count++;
 }
 console.log('Annotated conservative visibility bounds for',count,'models');
}
