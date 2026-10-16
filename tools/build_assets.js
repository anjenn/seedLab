const fs=require('node:fs');const path=require('node:path');const crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),E=require('../core/engine.js');
fs.writeFileSync(path.join(root,'assets','keywords.json'),JSON.stringify(E.keywords,null,2));
if(process.argv.includes('--keywords-only')){console.log(`${E.keywords.length} keywords written`);process.exit(0);}
const names=['Soft Rose','Cool Teal','Warm Cream','Deep Film','Pastel Blue','Natural Peach','Muted Sage','Bright Lavender','Crisp Gold','Matte Brown','Quiet Cyan','Dreamy Pink'];
for(let i=0;i<12;i++){
 const attrs={PresetType:'Normal',UUID:crypto.createHash('md5').update('seedlab-example-'+i).digest('hex').toUpperCase(),Version:'16.0',ProcessVersion:'11.0',SupportsColor:'True',SupportsMonochrome:'True',SupportsHighDynamicRange:'True',SupportsNormalDynamicRange:'True',SupportsSceneReferred:'True',SupportsOutputReferred:'True',CameraModelRestriction:'',Exposure2012:0,Contrast2012:(i%4)*10-15,Highlights2012:-20,Shadows2012:15,Whites2012:0,Blacks2012:8,Texture:-8,Clarity2012:-6,Dehaze:0,Vibrance:10,Saturation:-8,GrainAmount:i%3*8,HueAdjustmentRed:i%5-2,SaturationAdjustmentBlue:i%4*-5,LuminanceAdjustmentOrange:8};
 const fields=Object.entries(attrs).map(([k,v])=>` crs:${k}="${v}"`).join('\n');
 const xml=`<?xml version="1.0" encoding="UTF-8"?>\n<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"\n${fields}>\n<crs:Name><rdf:Alt><rdf:li xml:lang="x-default">SAMPLE ${i+1} - ${names[i]}</rdf:li></rdf:Alt></crs:Name>\n<crs:Group><rdf:Alt><rdf:li xml:lang="x-default">Seed Lab Samples</rdf:li></rdf:Alt></crs:Group>\n<crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 8</rdf:li><rdf:li>64, 58</rdf:li><rdf:li>128, 132</rdf:li><rdf:li>255, 250</rdf:li></rdf:Seq></crs:ToneCurvePV2012>\n</rdf:Description></rdf:RDF></x:xmpmeta>\n`;
 fs.writeFileSync(path.join(root,'tests','fixtures','seeds',`Sample_${String(i+1).padStart(2,'0')}.xmp`),xml);
}
console.log(`${E.keywords.length} keywords and 12 synthetic test seed XMPs written`);
