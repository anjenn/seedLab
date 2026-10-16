const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');const vm=require('node:vm');
const root=path.resolve(__dirname,'..');const E=require('../core/engine.js');
let tests=0;function test(name,f){f();tests++;console.log('PASS '+name);}
const seeds=Array.from({length:16},(_,i)=>({id:'seed-'+i,name:'씨드 '+i,values:{Exposure2012:0,Contrast2012:i-8,Highlights2012:-20,Shadows2012:12,Blacks2012:10,Whites2012:0,Texture:-5,Clarity2012:-3,Vibrance:12,Saturation:-4,Temperature:5600,Tint:8,HueAdjustmentRed:3,SaturationAdjustmentBlue:-20,GrainAmount:8,UnknownVendorSetting:123}}));
function request(extra){return Object.assign({seeds,keywordIds:['dreamy','rose','cyan','black_contrast'],count:48,fidelity:85,variation:70,randomSeed:1223},extra);}
test('44 unique keywords in six categories, synchronized with the UI catalog',()=>{
 assert.equal(E.keywords.length,44);assert.equal(new Set(E.keywords.map(x=>x.id)).size,44);
 assert.deepEqual([...new Set(E.keywords.map(x=>x.category))],['분위기','톤','따뜻한 색감','차가운 색감','팔레트','스타일']);
 assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root,'assets','keywords.json'),'utf8')),E.keywords);
 for(const keyword of E.keywords){
  assert.deepEqual(Object.keys(keyword.axes),E.axes);
  assert.ok(Object.values(keyword.axes).every(x=>Number.isFinite(x)&&x>=-1&&x<=1));
  assert.equal(E.prepare(request({count:1,keywordIds:[keyword.id]})).assignments[0].keyword,keyword.label);
 }
 assert.equal(E.prepare(request({count:1,keywordIds:[]})).assignments[0].keywordId,'natural');
});
test('16 seeds fairly assigned to 48 candidates',()=>{const a=E.prepare(request()).assignments;for(const s of seeds)assert.equal(a.filter(x=>x.seedId===s.id).length,3);});
test('up to 120 candidates, no exact duplicates',()=>{const r=E.generate(request({count:120,fidelity:60,variation:100}));assert.equal(r.candidates.length,120);assert.equal(new Set(r.candidates.map(x=>x.seedId+JSON.stringify(x.values))).size,120);});
test('bounds and unknown metadata protected over 80 configurations',()=>{
 for(let f=0;f<=100;f+=25)for(let v of [0,5,40,100])for(let rand=1;rand<=4;rand++){
  const r=E.generate(request({fidelity:f,variation:v,randomSeed:rand}));
  for(const c of r.candidates)for(const [k,n] of Object.entries(c.values)){
   assert.ok(Number.isFinite(n));assert.notEqual(k,'UnknownVendorSetting');
   if(k==='Temperature')assert.ok(n>=2000&&n<=50000);else assert.ok(n>=E.specs[k][0]&&n<=E.specs[k][1]);
   if(E.specs[k])assert.ok(Math.abs(c.delta[k])<=E.specs[k][2]*v/100*(E.specs[k][4]?(1-f/100):(.3+.7*(1-f/100)))+.51);
  }
 }
});
test('100 fidelity locks color anchors and white balance',()=>{const r=E.generate(request({fidelity:100}));for(const c of r.candidates){assert.equal(c.values.Temperature,undefined);for(const k in c.values)assert.equal(E.specs[k][4],0);}});
test('zero variation does not invent unique presets',()=>{const r=E.generate(request({variation:0}));assert.equal(r.candidates.length,seeds.length);assert.equal(r.warnings.length,32);for(const c of r.candidates)assert.deepEqual(c.values,{});});
test('JPG temperature uses a signed range, RAW uses Kelvin',()=>{const r=E.generate(request({seeds:[{id:'jpeg',name:'JPG',values:{Temperature:-10,Tint:-4}}],count:60,keywordIds:['cream_white','cool_blue'],fidelity:0,variation:100}));for(const c of r.candidates)if(c.values.Temperature!==undefined)assert.ok(c.values.Temperature>=-100&&c.values.Temperature<=100);});
test('AI axes clamped, malformed and duplicate indexes rejected',()=>{
 const q=request({count:2});const plans=E.prepare(q).assignments.map(a=>({index:a.index,reason:'설계',axes:Object.fromEntries(E.axes.map(k=>[k,900]))}));
 const r=E.generate(Object.assign(q,{aiPlans:plans}));assert.equal(r.candidates.length,2);assert.equal(r.candidates[0].mode,'ai');
 assert.throws(()=>E.generate(request({count:2,aiPlans:[plans[0],plans[0]]})),/index/);
 assert.throws(()=>E.generate(request({count:2,aiPlans:[{index:0,axes:{}},plans[1]]})),/axis/);
});
test('same random seed reproduces values; new seed varies them',()=>{assert.deepEqual(E.generate(request()),E.generate(request()));assert.notDeepEqual(E.generate(request()),E.generate(request({randomSeed:1230})));});
test('WSH JSON codec and actual engine run without modern built-ins',()=>{
 const box=vm.createContext({});vm.runInContext('JSON=undefined; Array.prototype.indexOf=undefined;',box);
 vm.runInContext(fs.readFileSync(path.join(root,'core','json_compat.js'),'utf8'),box);
 vm.runInContext(fs.readFileSync(path.join(root,'core','engine.js'),'utf8'),box);
 const text=JSON.stringify(request());box.input=text;
 const actual=vm.runInContext('JSON.stringify(SeedEngine.generate(JSON.parse(input)))',box);
 assert.deepEqual(JSON.parse(actual),E.generate(request()));
 for(const bad of ['{"x":1,}','[1,]','{"x":01}','{"x":"\\q"}','{"__proto__":{}}','true false'])assert.throws(()=>{box.input=bad;vm.runInContext('JSON.parse(input)',box);});
});
test('invalid requests rejected',()=>{assert.throws(()=>E.generate(request({seeds:[]})));assert.throws(()=>E.generate(request({count:121})));});
test('small variation reports fewer useful candidates instead of tiny duplicates',()=>{
 const r=E.generate(request({seeds:[seeds[0]],count:24,variation:1}));
 assert.equal(r.candidates.length,1);assert.equal(r.diversity.omittedCount,23);assert.equal(r.warnings.length,23);
});
test('same-seed candidates differ materially in at least one supported slider',()=>{
 const r=E.generate(request({seeds:[seeds[0]],count:24}));assert.ok(r.candidates.length>=4);
 for(let i=0;i<r.candidates.length;i++)for(let j=0;j<i;j++){
  const a=r.candidates[i].delta,b=r.candidates[j].delta;
  assert.ok(Object.keys({...a,...b}).some(k=>Math.abs((a[k]||0)-(b[k]||0))>=(k==='Exposure2012'?.078:k==='Temperature'?162.5:k==='Tint'?3.9:5.2)-1e-10));
 }
});
test('seed coverage warning, duplicate IDs, invalid counts and controls',()=>{
 assert.ok(E.generate(request({count:2})).warnings.some(w=>w.includes('14')));
 assert.throws(()=>E.generate(request({seeds:[seeds[0],seeds[0]]})),/seed ID/);
 for(const extra of [{count:1.5},{fidelity:null},{variation:Infinity},{fidelity:101},{variation:-1}])assert.throws(()=>E.generate(request(extra)));
 const weird=E.generate(request({seeds:[{id:'__proto__',name:'safe',values:{}}],count:1}));assert.equal(weird.candidates[0].seedId,'__proto__');
});
console.log(`${tests} tests passed`);
