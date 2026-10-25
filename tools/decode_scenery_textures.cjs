// Classic JPEG BLP can store alpha as a fourth JPEG channel. Pillow's generic
// BLP loader loses that channel, so use the same Warcraft-aware decoder as MDX.
const fs=require('fs'),path=require('path'),w=require('war3-model');
const root=path.resolve(__dirname,'..');
const source=JSON.parse(fs.readFileSync(path.join(root,'research/scenery-source.json'),'utf8'));
const converted=JSON.parse(fs.readFileSync(path.join(root,'research/scenery-conversion.json'),'utf8'));
const names=new Set([...converted.textures,...source.fields[0].tile_assets.map(t=>t.member),...source.models.map(m=>m.replacement).filter(Boolean)]);
const dir=path.join(root,'research/scenery-decoded');fs.mkdirSync(dir,{recursive:true});
const report=[];
for(const name of names){
 const clean=name.toLowerCase().replace(/[^a-z0-9._-]+/g,'_');
 const b=fs.readFileSync(path.join(root,'assets/source',clean));
 const img=w.getBLPImageData(w.decodeBLP(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength)),0);
 fs.writeFileSync(path.join(dir,clean+'.rgba'),Buffer.from(img.data));
 report.push({name:clean,width:img.width,height:img.height});
}
fs.writeFileSync(path.join(dir,'index.json'),JSON.stringify(report));
console.log('Decoded',report.length,'BLP textures with original alpha channels.');
