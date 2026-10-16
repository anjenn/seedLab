/* ES5 preset mixer. Pure numeric plans only; XML and opaque settings stay in the host. */
(function(root){
 'use strict';
 var groups=['tone','color','texture','curves'],labels={tone:'톤',color:'색감',texture:'질감',curves:'커브'};
 var curves=['ToneCurvePV2012','ToneCurvePV2012Red','ToneCurvePV2012Green','ToneCurvePV2012Blue'];
 var specs={},hues={SplitToningShadowHue:'SplitToningShadowSaturation',SplitToningHighlightHue:'SplitToningHighlightSaturation',ColorGradeMidtoneHue:'ColorGradeMidtoneSat',ColorGradeGlobalHue:'ColorGradeGlobalSat'};
 function own(o,k){return Object.prototype.hasOwnProperty.call(o,k);}
 function finite(n){return typeof n==='number'&&isFinite(n);}
 function arr(a){return Object.prototype.toString.call(a)==='[object Array]';}
 function round(n,p){var f=Math.pow(10,p||0),r=Math.round(n*f)/f;return r===0?0:r;}
 function add(names,group,min,max,def,precision){for(var i=0;i<names.length;i++)specs[names[i]]={group:group,min:min,max:max,neutral:def||0,precision:precision||0};}
 add(['Exposure2012'],'tone',-5,5,0,2);
 add(['Contrast2012','Highlights2012','Shadows2012','Whites2012','Blacks2012'],'tone',-100,100);
 add(['Vibrance','Saturation','SplitToningBalance','ColorGradeShadowLum','ColorGradeMidtoneLum','ColorGradeHighlightLum','ColorGradeGlobalLum'],'color',-100,100);
 add(['SplitToningShadowSaturation','SplitToningHighlightSaturation','ColorGradeMidtoneSat','ColorGradeGlobalSat'],'color',0,100);
 add(['SplitToningShadowHue','SplitToningHighlightHue','ColorGradeMidtoneHue','ColorGradeGlobalHue'],'color',0,360);
 add(['ColorGradeBlending'],'color',0,100,50);
 add(['Texture','Clarity2012','Dehaze'],'texture',-100,100);
 add(['GrainAmount'],'texture',0,100);add(['GrainSize'],'texture',0,100,25);add(['GrainFrequency'],'texture',0,100,50);
 var colors=['Red','Orange','Yellow','Green','Aqua','Blue','Purple','Magenta'];
 for(var i=0;i<colors.length;i++)add(['HueAdjustment'+colors[i],'SaturationAdjustment'+colors[i],'LuminanceAdjustment'+colors[i]],'color',-100,100);
 function text(s,max){return String(s||'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').slice(0,max);}
 function weights(a,n){
  if(!arr(a)||a.length!==n)throw Error('혼합 비율 개수가 프리셋 수와 다릅니다.');
  var sum=0,out=[],j;for(j=0;j<n;j++){if(!finite(a[j])||a[j]<0||a[j]>100)throw Error('혼합 비율은 0~100의 숫자여야 합니다.');sum+=a[j];}
  if(sum<=0)throw Error('혼합 비율의 합은 0보다 커야 합니다.');
  for(j=0;j<n;j++)out.push(a[j]/sum);return out;
 }
 function curve(c,label){
  if(!arr(c)||c.length<2||c.length>256)throw Error(label+': 커브 좌표를 읽을 수 없습니다. Lightroom에서 XMP로 다시 내보내세요.');
  for(var p=0;p<c.length;p++)if(!arr(c[p])||c[p].length!==2||!finite(c[p][0])||!finite(c[p][1])||c[p][0]<0||c[p][0]>255||c[p][1]<0||c[p][1]>255||(p&&c[p][0]<=c[p-1][0]))throw Error(label+': 커브 좌표가 잘못되었습니다.');
  return c;
 }
 function prepare(req){
  if(!arr(req.sources)||req.sources.length<2||req.sources.length>12)throw Error('혼합할 프리셋을 2~12개 등록하세요.');
  if(!finite(req.count)||req.count%1||req.count<1||req.count>24)throw Error('믹스매치 생성 개수는 1~24 정수여야 합니다.');
  if(!finite(req.variation)||req.variation<0||req.variation>100)throw Error('조합 탐색 폭은 0~100이어야 합니다.');
  var seen={},active=[],raw=[],base=null,n,k,s,g,hasBlend=false,changed=false;
  for(n=0;n<req.sources.length;n++){
   s=req.sources[n];if(!s||typeof s.id!=='string'||!s.id||seen['s:'+s.id]||!s.values||typeof s.values!=='object')throw Error('프리셋 ID가 없거나 중복되었습니다.');
   seen['s:'+s.id]=true;if(!finite(s.weight)||s.weight<0||s.weight>100)throw Error(s.name+': 비율은 0~100이어야 합니다.');
   if(s.weight>0){active.push(s);raw.push(s.weight);if(s.id===req.baseId)base=s;}
  }
  if(active.length<2)throw Error('비율이 0보다 큰 프리셋이 2개 이상 필요합니다.');
  if(!base)throw Error('기준 프리셋을 선택하고 비율을 0보다 크게 설정하세요.');
  if(!req.groups)throw Error('혼합할 항목을 선택하세요.');
  for(n=0;n<groups.length;n++){
   g=groups[n];k=req.groups[g];
   if(k==='blend'){hasBlend=true;changed=true;}else if(k!=='base'){
    var found=false;for(var q=0;q<active.length;q++)if(active[q].id===k)found=true;
    if(!found)throw Error(labels[g]+': 사용할 프리셋의 비율을 0보다 크게 설정하세요.');
    if(k!==req.baseId)changed=true;
   }
  }
  if(!changed)throw Error('최소 한 항목은 섞거나 다른 프리셋에서 가져오세요.');
  if(req.useAi&&!hasBlend)throw Error('AI 설계에는 비율대로 섞는 항목이 하나 이상 필요합니다.');
  for(n=0;n<active.length;n++){
   s=active[n];
   if((s.processVersion||'')!==(base.processVersion||''))throw Error('현상 버전이 다른 프리셋은 함께 섞을 수 없습니다. Lightroom에서 같은 현상 버전으로 다시 내보내세요.');
   if(!!s.monochrome!==!!base.monochrome)throw Error('컬러와 흑백 프리셋은 분리해서 섞어 주세요.');
   for(k in specs)if(own(specs,k)&&req.groups[specs[k].group]!=='base'&&own(s.values,k)){
    var v=s.values[k],sp=specs[k];if(!finite(v)||v<sp.min||v>sp.max)throw Error(s.name+' · '+k+': 지원 범위를 벗어난 보정값입니다.');
   }
   if(req.groups.curves!=='base')for(k=0;k<curves.length;k++)if(s.curves&&own(s.curves,curves[k]))curve(s.curves[curves[k]],s.name+' · '+curves[k]);
  }
  return {sources:active,base:base,weights:weights(raw,active.length),groups:req.groups,schema:schema(active.length)};
 }
 function schema(n){
  var props={},j;
  for(j=0;j<groups.length;j++)props[groups[j]]={type:'array',minItems:n,maxItems:n,items:{type:'number',minimum:0,maximum:100}};
  return {type:'object',additionalProperties:false,required:['plans'],properties:{plans:{type:'array',items:{type:'object',additionalProperties:false,required:['index','name','reason','weights'],properties:{index:{type:'integer'},name:{type:'string'},reason:{type:'string'},weights:{type:'object',additionalProperties:false,required:groups.slice(0),properties:props}}}}}};
 }
 function at(points,x){
  if(!points)return x;if(x<=points[0][0])return points[0][1];
  for(var n=1;n<points.length;n++)if(x<=points[n][0]){var a=points[n-1],b=points[n];return a[1]+(b[1]-a[1])*(x-a[0])/(b[0]-a[0]);}
  return points[points.length-1][1];
 }
 function matrix(prep,proposal,variation){
  var result={},g,n,j,rule,w;
  for(j=0;j<groups.length;j++){
   g=groups[j];rule=prep.groups[g];w=[];
   if(rule==='blend'){
    w=prep.weights.slice(0);
    if(proposal){var target=weights(proposal[g],prep.sources.length);for(n=0;n<w.length;n++)w[n]=w[n]*(1-variation*.5)+target[n]*variation*.5;}
   }else for(n=0;n<prep.sources.length;n++)w.push(prep.sources[n].id===(rule==='base'?prep.base.id:rule)?1:0);
   result[g]=w;
  }
  return result;
 }
 function blend(prep,table){
  var values={},outCurves={},delta={},k,n,j,sp,value,any,s,w,hue,x,y,best,bestWeight;
  for(k in specs)if(own(specs,k)){
   sp=specs[k];if(prep.groups[sp.group]==='base')continue;
   any=own(prep.base.values,k);for(n=0;n<prep.sources.length;n++)if(table[sp.group][n]>0&&own(prep.sources[n].values,k))any=true;
   // A missing field leaves the photo untouched. Only fields present in a participating
   // preset are introduced; missing contributions use documented neutral slider values.
   if(!any)continue;value=0;
   if(own(hues,k)){
    x=0;y=0;best=own(prep.base.values,k)?prep.base.values[k]:0;bestWeight=-1;
    for(n=0;n<prep.sources.length;n++){
     s=prep.sources[n];w=table.color[n]*(own(s.values,hues[k])?s.values[hues[k]]:0);hue=own(s.values,k)?s.values[k]:0;
     x+=Math.cos(hue*Math.PI/180)*w;y+=Math.sin(hue*Math.PI/180)*w;if(w>bestWeight){bestWeight=w;best=hue;}
    }
    value=Math.abs(x)+Math.abs(y)<1e-10?best:(Math.atan2(y,x)*180/Math.PI+360)%360;
   }else for(n=0;n<prep.sources.length;n++){s=prep.sources[n];value+=(own(s.values,k)?s.values[k]:sp.neutral)*table[sp.group][n];}
   value=round(Math.max(sp.min,Math.min(sp.max,value)),sp.precision);if(own(hues,k)&&value===360)value=0;
   values[k]=value;delta[k]=round(value-(own(prep.base.values,k)?prep.base.values[k]:sp.neutral),sp.precision);
  }
  if(prep.groups.curves!=='base')for(j=0;j<curves.length;j++){
   k=curves[j];any=!!(prep.base.curves&&own(prep.base.curves,k));var single=-1,contributors=0;
   for(n=0;n<prep.sources.length;n++)if(table.curves[n]>0){contributors++;single=n;if(prep.sources[n].curves&&own(prep.sources[n].curves,k))any=true;}
   if(!any)continue;
   if(contributors===1){outCurves[k]=(prep.sources[single].curves&&prep.sources[single].curves[k])||[[0,0],[255,255]];continue;}
   var xs=[0,64,128,192,255],points=[];
   for(var p=0;p<xs.length;p++){value=0;for(n=0;n<prep.sources.length;n++)value+=table.curves[n]*at(prep.sources[n].curves&&prep.sources[n].curves[k],xs[p]);points.push([xs[p],round(value)]);}
   outCurves[k]=points;
  }
  return {values:values,delta:delta,curves:outCurves};
 }
 function generate(req){
  var prep=prepare(req),plans=req.aiPlans,map={},out=[],seen={},warnings=[],seed=(req.randomSeed>>>0)||17;
  function random(){seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;}
  if(req.useAi){
   if(!arr(plans)||plans.length!==req.count)throw Error('AI 조합 개수가 요청과 다릅니다.');
   for(var i=0;i<plans.length;i++){
    var p=plans[i];if(!p||!finite(p.index)||p.index%1||p.index<0||p.index>=req.count||own(map,'i:'+p.index)||typeof p.name!=='string'||typeof p.reason!=='string'||!p.weights)throw Error('AI 조합의 번호 또는 설명이 잘못되었습니다.');
    for(var g=0;g<groups.length;g++)weights(p.weights[groups[g]],prep.sources.length);map['i:'+p.index]=p;
   }
  }
  for(var n=0;n<req.count;n++){
   var plan=req.useAi?map['i:'+n]:null,proposal=plan?plan.weights:null;
   if(!plan&&n>0){proposal={};for(g=0;g<groups.length;g++){var a=[];for(i=0;i<prep.weights.length;i++)a.push(prep.weights[i]*100*(.15+random()*.85));proposal[groups[g]]=a;}}
   var table=matrix(prep,proposal,req.variation/100),mixed=blend(prep,table),signature=JSON.stringify([mixed.values,mixed.curves]);
   if(seen['s:'+signature])continue;seen['s:'+signature]=true;
   var ratios={};for(g=0;g<groups.length;g++){a=[];for(i=0;i<prep.sources.length;i++)a.push({id:prep.sources[i].id,name:prep.sources[i].name,percent:round(table[groups[g]][i]*100,3)});ratios[groups[g]]=a;}
   out.push({index:out.length,name:plan?text(plan.name,80):'믹스매치 '+(n+1),reason:plan?text(plan.reason,1200):'지정한 비율과 항목별 선택으로 혼합했습니다.',baseId:prep.base.id,baseName:prep.base.name,values:mixed.values,delta:mixed.delta,curves:mixed.curves,ratios:ratios,mode:req.useAi?'mix_ai':'mix_local'});
  }
  warnings.push('화이트밸런스·프로필·LUT·마스크·크롭 및 지원하지 않는 설정은 기준 프리셋에서 유지합니다. 결과의 외관은 적용할 사진에 따라 달라집니다.');
  warnings.push('섞는 항목에서 일부 프리셋에 없는 슬라이더는 중립값으로 계산합니다. 여러 커브를 섞을 때는 5개 입력 밝기에서 보간하며, 사진을 렌더링한 결과와 동일한 혼합을 보장하지 않습니다.');
  if(out.length<req.count)warnings.push('보정값이 같은 후보 '+(req.count-out.length)+'개를 제외했습니다. 조합 탐색 폭을 높이거나 사용할 프리셋을 바꿔 보세요.');
  return {candidates:out,warnings:warnings};
 }
 var api={prepare:prepare,schema:schema,generate:generate,specs:specs,groups:groups,curveNames:curves};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.MixEngine=api;
}(this));
