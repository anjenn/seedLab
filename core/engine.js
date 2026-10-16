/* ES5 core shared by Windows Script Host and the Node test runner.
 * No network, no XML construction, no eval. All AI directions are bounded. */
(function (root) {
  'use strict';
  var axes = ['exposure','contrast','softness','warmth','magenta','saturation','shadowLift','red','green','blue','grain'];
  function vec(a){var r={},i;for(i=0;i<axes.length;i++)r[axes[i]]=a[i]||0;return r;}
  var tags=[
    ['dreamy','몽환적인','분위기',[.2,-.4,.8,0,.15,-.2,.4,0,0,0,0]],
    ['fairytale','동화적인','분위기',[.25,-.25,.6,.1,.15,.15,.3,.15,.1,.15,0]],
    ['romantic','로맨틱한','분위기',[.1,-.15,.45,.2,.4,-.1,.15,.25,0,0,0]],
    ['girlish','소녀스러운','분위기',[.25,-.25,.4,.1,.3,-.15,.2,.25,0,.1,0]],
    ['lovely','사랑스러운','분위기',[.2,-.1,.3,.25,.25,.2,.15,.4,0,0,0]],
    ['pure','청순한','분위기',[.3,-.2,.35,-.05,.05,-.25,.2,.05,0,.05,0]],
    ['mysterious','신비로운','분위기',[-.15,.15,.4,-.35,.3,-.15,.15,0,.1,.4,0]],
    ['fantasy','판타지한','분위기',[.1,.15,.4,-.1,.35,.3,.1,.2,.1,.35,0]],
    ['natural','자연스러운','분위기',[0,0,0,0,0,-.1,0,0,0,0,0]],
    ['relaxed','편안한','분위기',[.05,-.15,.2,.1,0,-.15,.15,0,0,0,0]],
    ['fresh','산뜻한','분위기',[.2,.05,-.05,-.05,0,.1,.05,0,.1,.05,0]],
    ['cozy','포근한','분위기',[.1,-.2,.35,.25,.05,-.15,.2,.1,0,0,0]],
    ['soft','부드러운','톤',[.1,-.4,.65,0,0,-.1,.2,0,0,0,0]],
    ['airy','밝고 가벼운','톤',[.6,-.25,.3,.1,0,-.1,.3,0,0,0,0]],
    ['clean','깨끗한','톤',[.2,.15,-.15,0,0,-.1,-.05,0,0,0,-.2]],
    ['radiant','화사한','톤',[.45,-.1,.2,.15,.1,.2,.2,.15,0,0,0]],
    ['calm','차분한','톤',[0,-.2,.2,-.1,0,-.4,.1,0,0,0,0]],
    ['dreamy_tone','드리미한','톤',[.3,-.5,.7,.05,.1,-.3,.55,0,0,.1,0]],
    ['emotive','감성적인','톤',[.05,-.2,.3,.15,.1,-.3,.3,.1,0,-.05,.15]],
    ['kitschy','키치한','톤',[.1,.35,-.2,.1,.3,.65,-.15,.4,.1,.3,0]],
    ['balanced','균형 잡힌','톤',[0,.05,0,0,0,0,0,0,0,0,0]],
    ['crisp','선명한','톤',[.05,.25,-.3,0,0,.1,-.1,0,0,0,0]],
    ['baby_pink','베이비 핑크','따뜻한 색감',[.25,-.35,.35,.05,.5,-.3,.25,.35,0,0,0]],
    ['rose','로즈 핑크','따뜻한 색감',[0,0,.1,.15,.6,.1,0,.6,-.1,0,0]],
    ['peach','피치','따뜻한 색감',[.15,-.1,.2,.4,.2,-.1,.1,.5,0,0,0]],
    ['milky_pink','밀키 핑크','따뜻한 색감',[.3,-.45,.5,.1,.35,-.45,.4,.25,0,0,0]],
    ['cream_white','크림 화이트','따뜻한 색감',[.35,-.3,.3,.35,.05,-.35,.25,.1,.05,0,0]],
    ['candy_pink','캔디 핑크','따뜻한 색감',[.15,.1,.1,.1,.65,.5,.05,.7,-.1,.05,0]],
    ['beige','베이지','따뜻한 색감',[.1,-.15,.15,.2,0,-.3,.1,.1,.05,0,0]],
    ['warm_brown','웜 브라운','따뜻한 색감',[-.1,.1,.05,.3,0,-.25,.05,.2,.05,-.1,0]],
    ['sky_blue','하늘빛','차가운 색감',[.3,-.2,.2,-.4,-.05,-.15,.2,0,.1,.4,0]],
    ['cool_blue','쿨 블루','차가운 색감',[0,.1,0,-.7,-.05,-.1,0,0,0,.6,0]],
    ['cyan','시안','차가운 색감',[0,.1,0,-.5,-.3,.1,0,0,.1,.65,0]],
    ['lavender','라벤더','차가운 색감',[.1,-.2,.2,-.35,.55,-.1,.1,.1,0,.5,0]],
    ['mint','민트','차가운 색감',[.2,-.2,.2,-.3,-.3,-.2,.2,0,.6,.1,0]],
    ['icy_blue','아이시 블루','차가운 색감',[.35,.15,-.2,-.6,-.1,-.3,.1,0,.15,.45,0]],
    ['cool_gray','쿨 그레이','차가운 색감',[0,.1,0,-.15,0,-.35,.05,0,0,.05,0]],
    ['blue_gray','블루 그레이','차가운 색감',[-.05,.1,.05,-.3,0,-.3,.1,0,.05,.2,0]],
    ['pastel','파스텔','팔레트',[.25,-.35,.3,0,0,-.6,.25,.1,.1,.1,0]],
    ['muted_pastel','저채도 파스텔','팔레트',[.15,-.3,.35,0,0,-.8,.3,.05,.05,.05,0]],
    ['milky_color','밀키 컬러','팔레트',[.3,-.5,.5,.05,.05,-.4,.5,.1,.1,.1,0]],
    ['candy_color','캔디 컬러','팔레트',[.2,.15,.05,.05,.2,.65,.05,.4,.25,.4,0]],
    ['clean_white','깨끗한 화이트','팔레트',[.3,.1,-.1,-.1,0,-.15,-.05,0,0,0,0]],
    ['black_contrast','블랙 대비','팔레트',[-.1,.65,-.1,0,0,.1,-.7,0,0,0,0]],
    ['color_accent','컬러 포인트','팔레트',[.05,.3,-.1,0,.05,-.15,-.15,.55,-.2,.3,0]],
    ['studio_backdrop','스튜디오 배경색','팔레트',[.15,.15,-.1,0,0,.3,0,.2,.25,.25,0]],
    ['neutral_palette','뉴트럴','팔레트',[0,0,.05,0,0,-.2,.05,0,0,0,0]],
    ['earth_tone','어스 톤','팔레트',[0,-.05,.1,.2,0,-.3,.1,.15,.15,-.1,0]],
    ['idol_editorial','아이돌 화보','스타일',[.3,.2,.15,.05,.15,.25,-.05,.2,.05,.15,0]],
    ['costume_editorial','코스튬 화보','스타일',[.1,.4,-.25,0,.1,.45,-.2,.25,.15,.25,0]],
    ['character_focus','캐릭터 중심','스타일',[.15,.3,-.15,0,.05,.15,-.1,.15,0,.1,0]],
    ['subculture','서브컬처 감성','스타일',[0,.25,.1,-.15,.35,.35,-.1,.25,.05,.4,0]],
    ['y2k','Y2K 감성','스타일',[.15,.45,-.3,-.1,.2,.55,-.25,.2,.1,.4,.1]],
    ['fairycore','페어리코어','스타일',[.25,-.35,.65,.1,.1,-.25,.4,.1,.35,.1,.1]],
    ['angelcore','엔젤코어','스타일',[.5,-.4,.7,-.05,.05,-.45,.4,.05,0,.1,0]],
    ['cute_fantasy','큐트 판타지','스타일',[.3,-.1,.35,.05,.35,.35,.2,.35,.1,.3,0]],
    ['daily_snap','데일리 스냅','스타일',[.1,.05,0,.05,0,.05,.05,0,0,0,0]],
    ['portrait','인물 사진','스타일',[.1,-.05,.2,.1,.05,-.1,.1,.1,0,0,0]],
    ['film','필름 감성','스타일',[0,-.15,.15,.1,.05,-.25,.3,.1,.05,-.05,.25]],
    ['minimal','미니멀','스타일',[.1,.15,-.05,0,0,-.3,-.05,0,0,0,0]]
  ];
  var keywords=[],i,j;
  for(i=0;i<tags.length;i++)keywords.push({id:tags[i][0],label:tags[i][1],category:tags[i][2],axes:vec(tags[i][3])});
  var defaultKeyword={id:'natural',label:'자연스러운',axes:vec([0,0,0,0,0,-.1,0,0,0,0,0])};
  // [min,max,max delta,default,style anchor flag]
  var specs={
    Exposure2012:[-5,5,.8,0,0],Contrast2012:[-100,100,30,0,0],Highlights2012:[-100,100,28,0,0],
    Shadows2012:[-100,100,28,0,0],Whites2012:[-100,100,22,0,0],Blacks2012:[-100,100,25,0,0],
    Texture:[-100,100,24,0,0],Clarity2012:[-100,100,22,0,0],Dehaze:[-100,100,12,0,0],
    Vibrance:[-100,100,24,0,1],Saturation:[-100,100,20,0,1],GrainAmount:[0,100,22,0,0],
    Tint:[-150,150,15,0,1],SplitToningBalance:[-100,100,20,0,1],
    SplitToningShadowSaturation:[0,100,14,0,1],SplitToningHighlightSaturation:[0,100,14,0,1],
    ColorGradeMidtoneSat:[0,100,14,0,1]
  };
  var colors=['Red','Orange','Yellow','Green','Aqua','Blue','Purple','Magenta'];
  for(i=0;i<colors.length;i++)for(j=0;j<3;j++)specs[['Hue','Saturation','Luminance'][j]+'Adjustment'+colors[i]]=[-100,100,j===0?12:18,0,1];
  function own(o,k){return Object.prototype.hasOwnProperty.call(o,k);}
  function clamp(n,a,b){return Math.min(b,Math.max(a,n));}
  function numeric(n){return typeof n==='number' && isFinite(n);}
  function rng(s){s=(s>>>0)||1234567;return function(){s=(1664525*s+1013904223)>>>0;return s/4294967296;};}
  function round(n,d){var p=Math.pow(10,d),r=Math.round(n*p)/p;return r===0?0:r;}
  function selected(req){var r=[],i;for(i=0;i<keywords.length;i++)if(req.keywordIds && req.keywordIds.indexOf(keywords[i].id)>=0)r.push(keywords[i]);return r;}
  function validateSettings(req){
    if(!numeric(req.fidelity)||req.fidelity<0||req.fidelity>100||!numeric(req.variation)||req.variation<0||req.variation>100)throw new Error('Invalid sliders.');
  }
  function prepare(req){
    validateSettings(req);
    if(!req.seeds || !req.seeds.length)throw new Error('At least one XMP seed is required.');
    var count=req.count;if(!numeric(count)||count%1||count<1 || count>120)throw new Error('Count must be 1..120.');
    var ids={},s;
    for(var n=0;n<req.seeds.length;n++){
      s=req.seeds[n];if(!s||typeof s.id!=='string'||!s.id||own(ids,'id:'+s.id)||!s.values||typeof s.values!=='object')throw new Error('Invalid or duplicate seed ID.');
      ids['id:'+s.id]=true;
    }
    var choices=selected(req);if(!choices.length)choices=[defaultKeyword];
    var a=[],i,seed,k,order=req.seeds.slice(),shuffle=rng(Number(req.randomSeed)||1),swap,at;
    for(i=order.length-1;i>0;i--){at=Math.floor(shuffle()*(i+1));swap=order[i];order[i]=order[at];order[at]=swap;}
    for(i=0;i<count;i++){
      seed=order[i%order.length];k=choices[(Math.floor(i/order.length)+i%order.length)%choices.length];
      a.push({index:i,seedId:seed.id,seedName:seed.name,keywordId:k.id,keyword:k.label,keywordAxes:k.axes});
    }
    return {assignments:a,axes:axes,keywords:choices};
  }
  function influences(a,k){
    if(k==='Exposure2012')return a.exposure;
    if(k==='Contrast2012')return a.contrast;
    if(k==='Highlights2012')return -.55*a.softness-.2*a.exposure;
    if(k==='Shadows2012')return .65*a.shadowLift-.2*a.contrast;
    if(k==='Whites2012')return .4*a.exposure-.35*a.softness;
    if(k==='Blacks2012')return .8*a.shadowLift-.25*a.contrast;
    if(k==='Texture' || k==='Clarity2012')return -a.softness;
    if(k==='Dehaze')return .4*a.contrast-.6*a.softness;
    if(k==='Vibrance' || k==='Saturation')return a.saturation;
    if(k==='GrainAmount')return a.grain;
    if(k==='Tint')return a.magenta;
    if(k==='SplitToningBalance')return a.warmth;
    if(/Sat(?:uration)?$/.test(k))return .5*a.saturation+.25*(Math.abs(a.warmth)+Math.abs(a.magenta));
    var col=k.replace(/^(Hue|Saturation|Luminance)Adjustment/,'');
    var p=(col==='Red'||col==='Orange'||col==='Magenta')?a.red:(col==='Yellow'||col==='Green')?a.green:a.blue;
    if(k.indexOf('HueAdjustment')===0)return .65*p+.2*a.warmth;
    if(k.indexOf('SaturationAdjustment')===0)return .5*a.saturation+.5*p;
    if(k.indexOf('LuminanceAdjustment')===0)return .3*a.exposure+.4*p;
    return 0;
  }
  // A slider-space separation heuristic, not a measured visual similarity.
  // Compare only candidates from the same seed; opaque curves/profiles remain intact.
  function distance(a,b,seed){
    var k,d=0,scale,all={};
    for(k in a)if(own(a,k))all[k]=true;
    for(k in b)if(own(b,k))all[k]=true;
    for(k in all)if(own(all,k)){
      scale=k==='Exposure2012'?.12:k==='Temperature'?(Number(seed.values.Temperature)>=1000?250:8):k==='Tint'?6:8;
      d=Math.max(d,Math.abs((own(a,k)?a[k]:0)-(own(b,k)?b[k]:0))/scale);
    }
    return d;
  }
  function generate(req){
    var prep=prepare(req),random=rng(Number(req.randomSeed)||1),f=clamp(Number(req.fidelity)/100,0,1),v=clamp(Number(req.variation)/100,0,1);
    if(!numeric(f)||!numeric(v))throw new Error('Invalid sliders.');
    var plans={},i,j,k,plan,seen={},out=[],warnings=[],seedById={},accepted={},minimumDistance=.65;
    for(i=0;i<req.seeds.length;i++)seedById['id:'+req.seeds[i].id]=req.seeds[i];
    if(req.count<req.seeds.length)warnings.push('요청한 후보 수가 씨드 수보다 적어 '+(req.seeds.length-req.count)+'개 씨드는 이번 생성에서 사용되지 않습니다.');
    if(req.aiPlans){
      if(req.aiPlans.length!==prep.assignments.length)throw new Error('AI returned the wrong candidate count.');
      for(i=0;i<req.aiPlans.length;i++){
        plan=req.aiPlans[i];if(!numeric(plan.index)||plan.index%1 ||plan.index<0||plan.index>=prep.assignments.length||own(plans,plan.index))throw new Error('Invalid AI index.');
        for(j=0;j<axes.length;j++)if(!plan.axes||!numeric(plan.axes[axes[j]]))throw new Error('Invalid AI axis.');
        plans[plan.index]=plan;
      }
    }
    for(i=0;i<prep.assignments.length;i++){
      var assignment=prep.assignments[i],seed=seedById['id:'+assignment.seedId],candidate,signature,attempt,delta,values,ax;
      var prior=accepted['id:'+seed.id]||(req.includeSeedBaseline?[{}]:[]),best=null,bestDistance=-1;
      for(attempt=0;attempt<48;attempt++){
        ax={};plan=plans[i];
        for(j=0;j<axes.length;j++){
          k=axes[j];var kw=assignment.keywordAxes[k],ai=plan?clamp(plan.axes[k],-1,1):kw;
          // Coherent artistic axes, bounded scatter, no indiscriminate seed averaging.
          ax[k]=clamp(.55*kw+.45*ai+(random()-.5)*.9,-1,1);
        }
        values={};delta={};
        for(k in specs)if(own(specs,k)){
          var sp=specs[k],has=own(seed.values,k),base=has?Number(seed.values[k]):sp[3];
          if(!numeric(base)||base<sp[0]||base>sp[1])continue;
          // Preserve missing style fields; only essential global sliders can be added.
          if(!has && (sp[4] || k==='GrainAmount'))continue;
          var budget=sp[2]*v*(sp[4]?(1-f):(.3+.7*(1-f)));
          var val=round(clamp(base+clamp(influences(ax,k),-1,1)*budget,sp[0],sp[1]),k==='Exposure2012'?2:0);
          if(val!==base){values[k]=val;delta[k]=round(val-base,2);}
        }
        if(own(seed.values,'Temperature')){
          var t=Number(seed.values.Temperature),raw=t>=1000;
          if(numeric(t)&&t>=(raw?2000:-100)&&t<=(raw?50000:100)){
            var tv=round(clamp(t+ax.warmth*(raw?1000:16)*v*(1-f),raw?2000:-100,raw?50000:100),0);
            if(tv!==t){values.Temperature=tv;delta.Temperature=tv-t;}
          }
        }
        signature=seed.id+'|'+JSON.stringify(values);
        if(own(seen,signature))continue;
        var nearest=Infinity;
        for(var p=0;p<prior.length;p++)nearest=Math.min(nearest,distance(delta,prior[p],seed));
        if(nearest>bestDistance){best={values:values,delta:delta,axes:ax,signature:signature};bestDistance=nearest;}
        if(!prior.length||(attempt>=15&&bestDistance>=minimumDistance))break;
      }
      if(!best||(prior.length&&bestDistance<minimumDistance)){warnings.push('후보 '+(i+1)+' 제외: 같은 씨드의 기존 후보와 보정값 차이가 작습니다. 변주 폭을 높이거나 개수를 줄여보세요.');continue;}
      values=best.values;delta=best.delta;ax=best.axes;signature=best.signature;
      seen[signature]=true;
      prior.push(delta);accepted['id:'+seed.id]=prior;
      candidate={index:i,seedId:seed.id,seedName:seed.name,keyword:assignment.keyword,keywordId:assignment.keywordId,
        values:values,delta:delta,axes:ax,reason:plan?String(plan.reason).slice(0,400):'씨드의 색상 앵커와 커브를 유지하며 '+assignment.keyword+' 방향으로 변형',
        mode:plan?'ai':'local',fidelity:req.fidelity,variation:req.variation};
      out.push(candidate);
    }
    return {candidates:out,warnings:warnings,keywordCount:keywords.length,version:'1.4.0',diversity:{method:'normalized-slider-distance',minimumDistance:minimumDistance,omittedCount:req.count-out.length}};
  }
  var api={keywords:keywords,axes:axes,specs:specs,prepare:prepare,generate:generate,distance:distance,validateSettings:validateSettings};
  if(typeof module!=='undefined' && module.exports)module.exports=api;else root.SeedEngine=api;
}(this));
