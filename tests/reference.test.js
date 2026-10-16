const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const R=require('../reference.js'),U=require('../usage.js'),root=path.resolve(__dirname,'..');
let count=0;function test(name,fn){fn();count++;console.log('PASS '+name)}
const copy=x=>JSON.parse(JSON.stringify(x));
function recipe(id='R001'){
 const values=Object.fromEntries(Object.keys(R.specs).map(k=>[k,0]));values.GrainSize=25;values.GrainFrequency=50;values.Contrast2012=12;values.Saturation=-10;
 const subject=Object.fromEntries(Object.keys(R.localSpecs).map(k=>[k,0]));subject.exposure=.3;subject.temperature=12;subject.clarity=-15;
 const background=Object.assign({},subject,{exposure:-.25,temperature:-20,clarity:10});
 return {referenceIds:[id],name:'로즈 필름',reason:'저채도 색감과 부드러운 대비',confidence:'medium',limitations:'조명과 소재의 영향은 분리하기 어렵습니다.',values,curves:Object.fromEntries(['ToneCurvePV2012','ToneCurvePV2012Red','ToneCurvePV2012Green','ToneCurvePV2012Blue'].map(k=>[k,[8,62,130,196,250]])),subject,background};
}
function req(extra={}){return Object.assign({referenceIds:['R001'],referenceMode:'common',recipes:[recipe()],count:12,keywordIds:['dreamy','rose'],fidelity:85,variation:70,randomSeed:12},extra)}
test('schemas are strict and all recipe properties are required',()=>{const c=R.contract();assert.equal(c.recipeSchema.additionalProperties,false);const p=c.recipeSchema.properties.recipes.items;assert.deepEqual(new Set(p.required),new Set(Object.keys(p.properties)));assert.equal(p.properties.values.additionalProperties,false);assert.equal(p.properties.curves.properties.ToneCurvePV2012.minItems,5);});
test('reference and observation IDs cannot be invented or repeated',()=>{const a={referenceId:'R001',style:'스타일',palette:'핑크',tone:'부드러운',lighting:'역광',subject:'밝음',background:'차가움',confidence:'medium',limitations:'한계'};assert.equal(R.validateObservations({referenceIds:['R001'],observations:[a]}).observations.length,1);assert.throws(()=>R.validateObservations({referenceIds:['R002'],observations:[a]}),/ID/);assert.throws(()=>R.validateObservations({referenceIds:['R001','R002'],observations:[a,a]}),/Duplicate/);});
test('common recipe must cover every photo, individual recipes remain separate',()=>{const q=req({referenceIds:['R001','R002']});assert.throws(()=>R.validateRecipes(q),/missing/);q.recipes[0].referenceIds.push('R002');assert.equal(R.validateRecipes(q).recipes.length,1);const x=req({referenceIds:['R001','R002'],referenceMode:'individual',recipes:[recipe(),recipe('R002')]});assert.equal(R.validateRecipes(x).recipes.length,2);x.recipes[1].referenceIds=['R001'];assert.throws(()=>R.validateRecipes(x),/multiple/);});
test('XML, camera profile, white balance and unknown slider fields are rejected',()=>{for(const k of ['CameraProfile','Temperature','Tint','CropTop','__bad']){const q=req();q.recipes[0].values[k]=500;assert.throws(()=>R.validateRecipes(q),/Unknown/);}const q=req();q.recipes[0].xml='<x/>';assert.throws(()=>R.validateRecipes(q),/Unknown/);});
test('nonnumeric recipe values are rejected instead of fabricated',()=>{for(const value of [NaN,Infinity,'20',null]){const q=req();q.recipes[0].values.Contrast2012=value;assert.throws(()=>R.validateRecipes(q),/numeric/);}});
test('finite slider overflow is clamped and disclosed for globals and masks',()=>{
 const q=req();q.recipes[0].values.Contrast2012=300;q.recipes[0].subject.exposure=3;q.recipes[0].background.temperature=-110;
 const before=copy(q),r=R.validateRecipes(q);assert.equal(r.recipes[0].values.Contrast2012,70);assert.equal(r.recipes[0].subject.exposure,2);assert.equal(r.recipes[0].background.temperature,-70);
 assert.equal(r.repairs.length,3);assert.equal(r.repairs[0].before,300);assert.equal(r.repairs[0].after,70);assert.equal(r.warnings.length,1);assert.deepEqual(q,before);
});
test('reversed curve points are pooled in place and audited without changing the input',()=>{
 const q=req();q.recipes[0].curves.ToneCurvePV2012=[0,40,20,192,255];const before=copy(q),r=R.validateRecipes(q);
 assert.deepEqual(r.recipes[0].curves.ToneCurvePV2012,[0,30,30,192,255]);assert.deepEqual(r.repairs[0].before,[0,40,20,192,255]);assert.deepEqual(r.repairs[0].after,[0,30,30,192,255]);
 assert.equal(r.repairs[0].field,'curves.ToneCurvePV2012');assert.deepEqual(r.repairs[0].referenceIds,['R001']);assert.deepEqual(q,before);
});
test('fractional and out-of-range curve points are bounded and rounded',()=>{
 const q=req();q.recipes[0].curves.ToneCurvePV2012Blue=[-8,64.5,128,192,256];const r=R.validateRecipes(q);
 assert.deepEqual(r.recipes[0].curves.ToneCurvePV2012Blue,[0,65,128,192,255]);assert.equal(r.repairs.length,1);
});
test('flat or fully descending curves use an explicitly reported neutral fallback',()=>{
 for(const values of [[42,42,42,42,42],[255,192,128,64,0],[-10,-9,-8,-7,-6]]){
  const q=req();q.recipes[0].curves.ToneCurvePV2012=values;const r=R.validateRecipes(q);
  assert.deepEqual(r.recipes[0].curves.ToneCurvePV2012,[0,64,128,192,255]);assert.equal(r.repairs[0].method,'identity-fallback');assert.match(r.warnings[0],/기본 직선/);
 }
});
test('malformed curve shape and nonnumeric points remain actionable failures',()=>{
 for(const values of [[0,64,128,192],[0,64,NaN,192,255],[0,64,null,192,255],[0,64,'128',192,255],{0:0,1:64,2:128,3:192,4:255,length:5}]){
  const q=req();q.recipes[0].curves.ToneCurvePV2012=values;assert.throws(()=>R.validateRecipes(q),/Curve ToneCurvePV2012/);
 }
});
test('valid curves are unchanged and repeated normalization is idempotent',()=>{
 const q=req(),r=R.validateRecipes(q);assert.deepEqual(r.recipes,q.recipes);assert.deepEqual(r.repairs,[]);assert.deepEqual(r.warnings,[]);
 q.recipes[0].curves.ToneCurvePV2012Red=[15,90,80,70,250];const fixed=R.validateRecipes(q);
 const again=R.validateRecipes(Object.assign({},q,{recipes:fixed.recipes}));assert.deepEqual(again.recipes,fixed.recipes);assert.deepEqual(again.repairs,[]);
});
test('stress: all channels stay bounded, ordered and nonconstant after normalization',()=>{
 let seed=17;const random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};
 for(let i=0;i<400;i++){
  const q=req();for(const k of Object.keys(q.recipes[0].curves))q.recipes[0].curves[k]=Array.from({length:5},()=>random()*600-150);
  const r=R.validateRecipes(q);for(const c of Object.values(r.recipes[0].curves)){assert.ok(c[0]<c[4]);c.forEach((y,p)=>assert.ok(Number.isInteger(y)&&y>=0&&y<=255&&(!p||y>=c[p-1])));}
 }
});
test('direct generation keeps repair warnings and uses corrected curves in every candidate',()=>{
 const q=req();q.recipes[0].curves.ToneCurvePV2012=[0,40,20,192,255];const r=R.generate(q);
 assert.equal(r.repairs.length,1);assert.ok(r.warnings.some(w=>w.includes('자동 보정')));for(const c of r.candidates)assert.deepEqual(c.curves.ToneCurvePV2012,[0,30,30,192,255]);
});
test('local sliders encode UI/100 and exposure EV/4 in XMP',()=>{const m=R.encodeMask(recipe().subject);assert.equal(m.LocalExposure2012,.075);assert.equal(m.LocalTemperature,.12);assert.equal(m.LocalClarity2012,-.15);const b=R.encodeMask(recipe().background);assert.equal(b.LocalTemperature,-.2);assert.notDeepEqual(m,b);});
test('first candidate exactly preserves the estimated recipe and its RGB curves',()=>{const q=req(),r=R.generate(q);assert.ok(r.candidates.length>1&&r.candidates.length<=12);assert.deepEqual(r.candidates[0].values,q.recipes[0].values);assert.deepEqual(r.candidates[0].curves,q.recipes[0].curves);assert.deepEqual(r.candidates[0].subject,q.recipes[0].subject);assert.equal(r.candidates[0].keywordId,'reference');});
test('24 references supported with fair extra variants and no dropped source',()=>{const ids=Array.from({length:24},(_,i)=>'R'+i),q=req({referenceMode:'individual',referenceIds:ids,recipes:ids.map(recipe),count:96});const r=R.generate(q);assert.equal(r.candidates.length,96);for(const id of ids)assert.equal(r.candidates.filter(c=>c.referenceIds[0]===id).length,4);});
test('zero variation excludes duplicates of the base recipe',()=>{const r=R.generate(req({variation:0,count:24}));assert.equal(r.candidates.length,1);assert.ok(r.warnings.some(s=>s.includes('중복')));});
test('reference variants obey the stricter recipe bounds at slider limits',()=>{const q=req({count:120,fidelity:0,variation:100});for(const k of Object.keys(R.specs))q.recipes[0].values[k]=R.specs[k][1];const r=R.generate(q);for(const c of r.candidates)for(const [k,v] of Object.entries(c.values))assert.ok(v>=R.specs[k][0]&&v<=R.specs[k][1]);assert.equal(new Set(r.candidates.map(c=>JSON.stringify([c.values,c.subject,c.background]))).size,r.candidates.length);});
test('web searches counted separately from open/find actions; citations deduplicated',()=>{const r=R.researchMeta({output:[{type:'web_search_call',action:{type:'search',sources:[{url:'https://adobe.com/a',title:'문서'},{url:'javascript:bad'}]}},{type:'web_search_call',action:{type:'open_page'}},{type:'web_search_call',action:{type:'find_in_page'}},{type:'message',content:[{type:'output_text',text:'검색한 방법',annotations:[{type:'url_citation',url:'https://adobe.com/a',title:'문서'},{type:'url_citation',url:'https://adobe.com/b',title:'문서 2'}]}]}]});assert.equal(r.searchCalls,1);assert.equal(r.sources.length,2);assert.equal(r.text,'검색한 방법');});
test('search fees are added to token cost without inventing token usage',()=>{const cost=U.estimateCost({model:'gpt-6-luna',usage:{input_tokens:10000,output_tokens:5000},serviceTier:'default',searchCalls:2});assert.equal(cost.tokenUSD,.0035);assert.equal(cost.searchUSD,.02);assert.equal(cost.estimatedUSD,.0235);assert.equal(U.estimateCost({model:'unknown',usage:{input_tokens:10,output_tokens:20},searchCalls:2}).estimatedUSD,null);assert.equal(U.estimateCost({model:'gpt-6-luna',usage:{input_tokens:10,output_tokens:20},searchCalls:-1}).estimatedUSD,null);});
test('reference phases and search counts survive ledger aggregation and dedup',()=>{const e={eventId:'one',kind:'api',runId:'run',localDate:'2026-10-16',model:'gpt-6-luna',mode:'reference',phase:'reference_research',usageKnown:true,status:'completed',inputTokens:100,outputTokens:20,webSearchCalls:2,searchUSD:.02,estimatedUSD:.02002};const r=U.summarize({today:'2026-10-16',days:7,events:[e,e,{eventId:'start',kind:'run_start',runId:'run',model:'gpt-6-luna',localDate:e.localDate,mode:'reference'}]});assert.equal(r.totals.webSearchCalls,2);assert.equal(r.totals.referenceRuns,1);assert.equal(r.totals.totalTokens,120);assert.equal(r.calls[0].Phase,'reference_research');assert.equal(r.runs[0].Mode,'레퍼런스');});
test('actual reference core works in legacy WSH-compatible VM',()=>{const box=vm.createContext({});vm.runInContext('JSON=undefined; Array.prototype.indexOf=undefined; Array.prototype.filter=undefined; Array.prototype.map=undefined;',box);for(const name of ['json_compat.js','engine.js','reference.js'])vm.runInContext(fs.readFileSync(path.join(root,name),'utf8'),box);box.input=JSON.stringify(req());assert.deepEqual(JSON.parse(vm.runInContext('JSON.stringify(ReferenceEngine.generate(JSON.parse(input)))',box)),R.generate(req()));});
test('insufficient counts and invalid confidence fail before export',()=>{assert.throws(()=>R.generate(req({count:0})),/Count/);const q=req();q.recipes[0].confidence='100%';assert.throws(()=>R.validateRecipes(q),/confidence/);});
if(process.argv.includes('--fixtures')){
 const p=req({count:4});p.recipes[0].referenceIds=['R001','R002'];
 const obs=['R001','R002'].map(referenceId=>({referenceId,style:'핑크 필름',palette:'로즈',tone:'부드러운',lighting:'조명 영향 있음',subject:'인물은 밝음',background:'배경은 차가움',confidence:'medium',limitations:'추정값'}));
 const response=(id,output)=>({id,model:'gpt-6-luna',status:'completed',service_tier:'default',usage:{input_tokens:1000,output_tokens:500,input_tokens_details:{cached_tokens:0},output_tokens_details:{reasoning_tokens:100}},output});
 const message=obj=>({type:'message',content:[{type:'output_text',text:JSON.stringify(obj),annotations:[]}]});
 fs.writeFileSync(path.join(__dirname,'reference-fixtures.json'),JSON.stringify({recipes:p.recipes,referenceIds:['R001','R002'],responses:[response('test-analysis',[message({observations:obs})]),response('test-search',[{type:'web_search_call',action:{type:'search',sources:[{url:'https://helpx.adobe.com/lightroom/desktop/edit-photos/masking.html',title:'Lightroom masks'}]}},{type:'message',content:[{type:'output_text',text:'색감은 HSL과 커브, 인물과 배경은 별도 마스크로 조절합니다.',annotations:[]}]}]),response('test-recipe',[message({recipes:p.recipes})])]},null,2));
}
test('base-only recipes validate controls, and shortfall is explicit',()=>{
 assert.throws(()=>R.generate(req({count:1,fidelity:NaN})),/sliders/);
 const r=R.generate(req({count:24,variation:1}));assert.equal(r.candidates.length,1);assert.equal(r.diversity.omittedCount,23);
 assert.ok(r.warnings.some(w=>w.includes('23')));
});
console.log(`${count} reference tests passed`);
