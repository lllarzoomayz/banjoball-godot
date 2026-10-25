const fs=require('fs'),path=require('path'),w=require('war3-model');
const root=path.resolve(__dirname,'..');
const forceModels=process.argv.includes('--models');
const forceAll=process.argv.includes('--all');
const filesIndex=process.argv.indexOf('--files');
const explicitFiles=filesIndex<0?null:new Set(process.argv.slice(filesIndex+1));
const selected=new Set();
if(forceModels){
 for(const file of fs.readdirSync(path.join(root,'assets/models')).filter(x=>x.endsWith('.json'))){
  const m=JSON.parse(fs.readFileSync(path.join(root,'assets/models',file)));
  for(const t of m.textures)if(t.Image)selected.add(t.Image.toLowerCase().replace(/[^a-z0-9._-]+/g,'_'));
 }
}
for(const name of fs.readdirSync(path.join(root,'assets/source')).filter(x=>x.endsWith('.blp')&&(!forceModels||selected.has(x))&&(!explicitFiles||explicitFiles.has(x)))){
 const png=path.join(root,'assets/textures',name+'.png');
 if(fs.existsSync(png)&&!forceModels&&!explicitFiles&&!forceAll)continue;
 const b=fs.readFileSync(path.join(root,'assets/source',name));
 const img=w.getBLPImageData(w.decodeBLP(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength)),0);
 fs.writeFileSync(path.join(root,'assets/source',name+'.rgba'),Buffer.from(img.data));
 fs.writeFileSync(path.join(root,'assets/source',name+'.size'),JSON.stringify([img.width,img.height]));
 console.log('Decoded',name,img.width,img.height);
}
