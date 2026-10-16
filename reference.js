/* ES5 reference-photo recipe contracts and bounded candidate generation.
 * The model supplies data, never XML, mask geometry, profiles, or code. */
(function(root){
 'use strict';
 var E=typeof module!=='undefined'&&module.exports?require('./engine.js'):root.SeedEngine;
 function own(o,k){return Object.prototype.hasOwnProperty.call(o,k);}
 function keys(o){var a=[],k;for(k in o)if(own(o,k))a.push(k);return a;}
 function finite(n){return typeof n==='number'&&isFinite(n);}
 function clamp(n,a,b){return Math.min(b,Math.max(a,n));}
 function round(n,p){var f=Math.pow(10,p||0),r=Math.round(n*f)/f;return r===0?0:r;}
 function obj(props){return {type:'object',additionalProperties:false,properties:props,required:keys(props)};}
 function str(){return {type:'string'};}
 function numbers(specs){var p={},k;for(k in specs)if(own(specs,k))p[k]={type:'number',minimum:specs[k][0],maximum:specs[k][1]};return obj(p);}
 var specs={Exposure2012:[-1.5,1.5],Contrast2012:[-70,70],Highlights2012:[-100,100],Shadows2012:[-100,100],Whites2012:[-100,100],Blacks2012:[-100,100],Texture:[-60,60],Clarity2012:[-60,60],Dehaze:[-40,40],Vibrance:[-80,80],Saturation:[-70,70],GrainAmount:[0,65],GrainSize:[0,100],GrainFrequency:[0,100],SplitToningShadowHue:[0,360],SplitToningShadowSaturation:[0,60],SplitToningHighlightHue:[0,360],SplitToningHighlightSaturation:[0,60],SplitToningBalance:[-100,100]};
 var colors=['Red','Orange','Yellow','Green','Aqua','Blue','Purple','Magenta'],i,j;
 for(i=0;i<colors.length;i++)for(j=0;j<3;j++)specs[['Hue','Saturation','Luminance'][j]+'Adjustment'+colors[i]]=[-100,100];
 var localSpecs={exposure:[-2,2],contrast:[-70,70],highlights:[-100,100],shadows:[-100,100],whites:[-100,100],blacks:[-100,100],temperature:[-70,70],tint:[-70,70],saturation:[-70,70],texture:[-60,60],clarity:[-60,60],dehaze:[-40,40]};
 var localNames={exposure:'LocalExposure2012',contrast:'LocalContrast2012',highlights:'LocalHighlights2012',shadows:'LocalShadows2012',whites:'LocalWhites2012',blacks:'LocalBlacks2012',temperature:'LocalTemperature',tint:'LocalTint',saturation:'LocalSaturation',texture:'LocalTexture',clarity:'LocalClarity2012',dehaze:'LocalDehaze'};
 var curveNames=['ToneCurvePV2012','ToneCurvePV2012Red','ToneCurvePV2012Green','ToneCurvePV2012Blue'];
 var observationFields=['referenceId','style','palette','tone','lighting','subject','background','limitations'];
 function contract(){
  var obs={},curves={},k;
  for(i=0;i<observationFields.length;i++)obs[observationFields[i]]=str();
  obs.confidence={type:'string','enum':['low','medium','high']};
  for(i=0;i<curveNames.length;i++)curves[curveNames[i]]={type:'array',minItems:5,maxItems:5,items:{type:'integer',minimum:0,maximum:255}};
  return {observationsSchema:obj({observations:{type:'array',items:obj(obs)}}),recipeSchema:obj({recipes:{type:'array',items:obj({referenceIds:{type:'array',items:str()},name:str(),reason:str(),confidence:{type:'string','enum':['low','medium','high']},limitations:str(),values:numbers(specs),curves:obj(curves),subject:numbers(localSpecs),background:numbers(localSpecs)})}}),settings:specs,maskSliders:localSpecs,curveInputPoints:[0,64,128,192,255]};
 }
 function exact(o,allowed,label){
  if(!o||typeof o!=='object'||Object.prototype.toString.call(o)==='[object Array]')throw new Error('Invalid '+label);
  var k;for(k in o)if(own(o,k)&&allowed.indexOf(k)<0)throw new Error('Unknown '+label+' field: '+k);
  for(var n=0;n<allowed.length;n++)if(!own(o,allowed[n]))throw new Error('Missing '+label+' field: '+allowed[n]);
 }
 function bounded(o,s,label){exact(o,keys(s),label);var r={},k;for(k in s)if(own(s,k)){if(!finite(o[k])||o[k]<s[k][0]||o[k]>s[k][1])throw new Error('Out of range '+label+': '+k);r[k]=round(o[k],k==='Exposure2012'||k==='exposure'?2:0);}return r;}
 function clean(s,max){if(typeof s!=='string')throw new Error('Invalid text field');return s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').slice(0,max);}
 function confidence(s){if(['low','medium','high'].indexOf(s)<0)throw new Error('Invalid confidence');return s;}
 function ids(a,expected,label){
  if(Object.prototype.toString.call(a)!=='[object Array]'||!a.length)throw new Error('Missing '+label+' IDs');
  var used={},r=[];for(var n=0;n<a.length;n++){if(typeof a[n]!=='string'||expected.indexOf(a[n])<0||used['i:'+a[n]])throw new Error('Invalid '+label+' ID');used['i:'+a[n]]=true;r.push(a[n]);}return r;
 }
 function validateObservations(req){
  var expected=req.referenceIds,a=req.observations,r=[],seen={};
  if(!a||a.length!==expected.length)throw new Error('Observation count mismatch');
  for(var n=0;n<a.length;n++){
   var o=a[n],v={},k;exact(o,observationFields.concat(['confidence']),'observation');ids([o.referenceId],expected,'reference');
   if(seen['i:'+o.referenceId])throw new Error('Duplicate reference observation');seen['i:'+o.referenceId]=true;
   for(k in o)if(own(o,k))v[k]=k==='confidence'?confidence(o[k]):clean(o[k],k==='referenceId'?80:1200);
   r.push(v);
  }
  return {observations:r};
 }
 function validateRecipes(req){
  var expected=req.referenceIds,a=req.recipes,r=[],seen={},common=req.referenceMode==='common';
  if(!a||a.length!==(common?1:expected.length))throw new Error('Recipe count mismatch');
  for(var n=0;n<a.length;n++){
   var o=a[n],v={},k,c;exact(o,['referenceIds','name','reason','confidence','limitations','values','curves','subject','background'],'recipe');
   v.referenceIds=ids(o.referenceIds,expected,'recipe');if(!common&&v.referenceIds.length!==1)throw new Error('Per-photo recipe must use one reference');
   for(var m=0;m<v.referenceIds.length;m++){k='i:'+v.referenceIds[m];if(seen[k])throw new Error('Reference appears in multiple recipes');seen[k]=true;}
   v.name=clean(o.name,80)||'Reference Style';v.reason=clean(o.reason,1600);v.limitations=clean(o.limitations,1600);v.confidence=confidence(o.confidence);
   v.values=bounded(o.values,specs,'global');v.subject=bounded(o.subject,localSpecs,'subject');v.background=bounded(o.background,localSpecs,'background');
   exact(o.curves,curveNames,'curves');v.curves={};
   for(m=0;m<curveNames.length;m++){
    k=curveNames[m];c=o.curves[k];if(!c||c.length!==5)throw new Error('Curve must have five points');
    v.curves[k]=[];for(var p=0;p<5;p++){if(!finite(c[p])||Math.floor(c[p])!==c[p]||c[p]<0||c[p]>255||(p&&c[p]<c[p-1]))throw new Error('Curve must be monotonic within 0..255');v.curves[k].push(c[p]);}
   }
   r.push(v);
  }
  for(n=0;n<expected.length;n++)if(!seen['i:'+expected[n]])throw new Error('Reference missing from recipes');
  return {recipes:r};
 }
 // Lightroom local XMP: exposure = EV/4, other supported local sliders = UI/100.
 function encodeMask(sliders){var a=bounded(sliders,localSpecs,'mask'),r={},k;for(k in a)if(own(a,k))r[localNames[k]]=round(k==='exposure'?a[k]/4:a[k]/100,4);return r;}
 function maskVariant(base,axes,strength){
  var a={},k;for(k in base)if(own(base,k))a[k]=base[k];
  var deltas={exposure:axes.exposure*.2,contrast:axes.contrast*8,temperature:axes.warmth*6,tint:axes.magenta*6,saturation:axes.saturation*8,texture:-axes.softness*6,clarity:-axes.softness*6};
  for(k in deltas)if(own(deltas,k))a[k]=round(clamp(a[k]+deltas[k]*strength,localSpecs[k][0],localSpecs[k][1]),k==='exposure'?2:0);
  return a;
 }
 function generate(req){
  E.validateSettings(req);
  var recipes=validateRecipes(req).recipes,count=req.count,n,k;
  if(!finite(count)||Math.floor(count)!==count||count<recipes.length||count>120)throw new Error('Count must cover every recipe and be <=120');
  var seeds=[],seedMap={},lookup={},seen={},out=[],zero={},warnings=['사진의 원래 보정값을 복원한 결과가 아닌 시각적 스타일 추정입니다. 조명·피사체·카메라와 적용할 원본에 따라 결과가 달라집니다.'];
  for(n=0;n<E.axes.length;n++)zero[E.axes[n]]=0;
  for(n=0;n<recipes.length;n++){var s={id:'reference-'+n,name:recipes[n].name,values:recipes[n].values};seeds.push(s);seedMap[s.id]=s;lookup[s.id]=recipes[n];}
  var extras=[];
  if(count>seeds.length){extras=E.generate({seeds:seeds,count:count-seeds.length,fidelity:req.fidelity,variation:req.variation,keywordIds:req.keywordIds,randomSeed:req.randomSeed,includeSeedBaseline:true}).candidates;}
  for(n=0;n<seeds.length+extras.length;n++){
   var base=n<seeds.length,original=base?null:extras[n-seeds.length],seed=base?seeds[n]:seedMap[original.seedId],recipe=lookup[seed.id],values={},delta={},ax=base?zero:original.axes;
   for(k in recipe.values)if(own(recipe.values,k))values[k]=recipe.values[k];
   if(!base)for(k in original.values)if(own(original.values,k)){values[k]=original.values[k];delta[k]=original.delta[k];}
   // The reference contract is stricter than the seed engine's full slider bounds.
   for(k in values)if(own(values,k)){values[k]=clamp(values[k],specs[k][0],specs[k][1]);if(!base&&own(delta,k))delta[k]=round(values[k]-recipe.values[k],2);}
   values=bounded(values,specs,'global');
   var strength=base?0:clamp(Number(req.variation)||0,0,100)/100*(1-clamp(Number(req.fidelity)||0,0,100)/100);
   var sub=maskVariant(recipe.subject,ax,strength),bg=maskVariant(recipe.background,ax,strength);
   var sig=seed.id+'|'+JSON.stringify(values)+'|'+JSON.stringify(sub)+'|'+JSON.stringify(bg);if(seen[sig])continue;
   var tooClose=false;
   if(!base)for(var q=0;q<out.length;q++)if(out[q].seedId===seed.id&&E.distance(delta,out[q].delta,seed)<.65){tooClose=true;break;}
   if(tooClose)continue;seen[sig]=true;
   out.push({index:out.length,seedId:seed.id,seedName:recipe.name,keyword:base?'레퍼런스 추정':original.keyword,keywordId:base?'reference':original.keywordId,values:values,delta:delta,curves:recipe.curves,axes:ax,reason:recipe.reason,confidence:recipe.confidence,limitations:recipe.limitations,referenceIds:recipe.referenceIds,mode:'reference',fidelity:req.fidelity,variation:req.variation,subject:sub,background:bg,encodedSubject:encodeMask(sub),encodedBackground:encodeMask(bg)});
  }
  if(out.length<count)warnings.push('중복·유사 후보 '+(count-out.length)+'개를 제외해 '+out.length+'개를 생성했습니다. 변주 폭을 높이면 후보를 더 만들 수 있습니다.');
  return {candidates:out,warnings:warnings,diversity:{method:'normalized-slider-distance',minimumDistance:.65,omittedCount:count-out.length}};
 }
 function researchMeta(req){
  var a=req.output||[],sources=[],seen={},calls=0,texts=[],i,j;
  function add(url,title){if(typeof url!=='string'||!/^https?:\/\//i.test(url)||/[\u0000-\u0020]/.test(url)||seen['u:'+url])return;seen['u:'+url]=true;sources.push({url:url,title:typeof title==='string'?title.slice(0,300):url});}
  for(i=0;i<a.length;i++){
   var item=a[i];if(item.type==='web_search_call'){
    if(item.action&&item.action.type==='search')calls++;
    var src=item.action&&item.action.sources||[];for(j=0;j<src.length;j++)add(src[j].url,src[j].title);
   }
   if(item.type==='message')for(j=0;j<(item.content||[]).length;j++){
    var part=item.content[j];if(part.type==='output_text'){texts.push(String(part.text||''));var ann=part.annotations||[];for(var p=0;p<ann.length;p++)if(ann[p].type==='url_citation')add(ann[p].url,ann[p].title);}
   }
  }
  return {searchCalls:calls,sources:sources,text:texts.join('\n').slice(0,20000)};
 }
 var api={contract:contract,validateObservations:validateObservations,validateRecipes:validateRecipes,generate:generate,encodeMask:encodeMask,researchMeta:researchMeta,specs:specs,localSpecs:localSpecs};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.ReferenceEngine=api;
}(this));
