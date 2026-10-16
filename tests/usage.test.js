const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const U=require('../core/usage.js');let passed=0;
function test(name,fn){fn();passed++;console.log('PASS '+name);}
function event(id,date='2026-10-14',extra={}){return Object.assign({eventId:id,kind:'api',runId:'run-'+id,timestampUtc:date+'T03:00:00Z',localDate:date,localTime:date+' 12:00:00',model:'gpt-6-luna',status:'completed',usageKnown:true,inputTokens:8000,outputTokens:4000,cachedTokens:2000,reasoningTokens:1500,estimatedUSD:.00262},extra);}
function sum(events,extra={}){return U.summarize(Object.assign({events,today:'2026-10-14',days:7,model:'all'},extra));}
test('empty ledger has seven zero-filled dates and no invented use',()=>{const r=sum([]);assert.equal(r.daily.length,7);assert.equal(r.totals.totalTokens,0);assert.equal(r.totals.calls,0);assert.equal(r.changePercent,null);});
test('pending-to-response and repeated response counted once',()=>{const e=event('call');const r=sum([Object.assign({},e,{status:'pending',usageKnown:false}),e,e]);assert.equal(r.totals.calls,1);assert.equal(r.totals.totalTokens,12000);assert.equal(r.totals.reasoningTokens,1500);assert.equal(r.totals.cachedTokens,2000);assert.equal(r.totals.unknownCalls,0);});
test('known incomplete usage kept, failed unknown usage excluded',()=>{const r=sum([event('partial','2026-10-14',{status:'incomplete',outputTokens:500}),event('timeout','2026-10-14',{status:'failed',usageKnown:false,estimatedUSD:null})]);assert.equal(r.totals.calls,2);assert.equal(r.totals.totalTokens,8500);assert.equal(r.totals.failedCalls,2);assert.equal(r.totals.unknownCalls,1);assert.equal(r.calls.find(x=>x.EventId==='timeout').Total,null);});
test('calendar range boundaries and previous period comparison',()=>{const r=sum([event('prev','2026-10-07',{inputTokens:1000,outputTokens:1000}),event('first','2026-10-08'),event('last','2026-10-14'),event('future','2026-10-15')]);assert.equal(r.start,'2026-10-08');assert.equal(r.totals.calls,2);assert.equal(r.previous.totalTokens,2000);assert.equal(r.changePercent,1100);});
test('generation progress / completion does not inflate run or preset count',()=>{const base=event('start','2026-10-14',{kind:'run_start',runId:'job',requestedCount:24});const progress=event('end','2026-10-14',{kind:'run_result',runId:'job',status:'exporting',generatedCount:10});const end=Object.assign({},progress,{status:'completed',generatedCount:24});const r=sum([base,progress,end]);assert.equal(r.totals.runs,1);assert.equal(r.totals.completedRuns,1);assert.equal(r.totals.generatedPresets,24);assert.equal(r.totals.calls,0);});
test('local generation appears without AI token use',()=>{const r=sum([event('start','2026-10-14',{kind:'run_start',runId:'offline',model:'local'}),event('end','2026-10-14',{kind:'run_result',runId:'offline',model:'local',status:'completed',generatedCount:12})]);assert.equal(r.totals.runs,1);assert.equal(r.totals.totalTokens,0);assert.equal(r.totals.generatedPresets,12);});
test('model filter and model split conserve token totals',()=>{const es=[event('a'),event('b','2026-10-14',{model:'gpt-6.1-sol',inputTokens:5000,outputTokens:2000})];const a=sum(es),b=sum(es,{model:'gpt-6.1-sol'});assert.equal(b.totals.totalTokens,7000);assert.equal(a.models.reduce((n,m)=>n+m.totalTokens,0),19000);assert.deepEqual(a.allModels.sort(),['gpt-6-luna','gpt-6.1-sol'].sort());});
test('90-day weekly buckets preserve exact daily values',()=>{const r=sum([event('first','2026-07-20'),event('last')],{days:90});assert.equal(r.daily.length,90);assert.equal(r.chart.length,13);assert.equal(r.chartUnit,'주별');assert.equal(r.chart.reduce((n,d)=>n+d.totalTokens,0),r.totals.totalTokens);});
test('leap day and all-history range are calendar safe',()=>{const r=U.summarize({events:[event('leap','2024-02-29')],today:'2024-03-01',days:3});assert.deepEqual(r.daily.map(d=>d.date),['2024-02-28','2024-02-29','2024-03-01']);assert.equal(sum([event('early','2026-10-01')],{days:'all'}).daily.length,14);});
test('corrupt / impossible dates skipped, unknown costs stay unknown',()=>{const r=sum([event('bad','2026-02-30'),null,event('ok','2026-10-14',{estimatedUSD:null})]);assert.equal(r.discardedEvents,2);assert.equal(r.totals.costUnknownCalls,1);assert.equal(r.calls[0].USD,null);assert.throws(()=>sum([],{today:'bad'}));});
test('editable model IDs cannot modify object prototypes',()=>{const r=sum([event('a','2026-10-14',{model:'__proto__'}),event('b','2026-10-14',{model:'constructor'})]);assert.equal(r.models.length,2);assert.equal(r.totals.calls,2);assert.equal(r.totals.totalTokens,24000);});
test('Standard model costs, cache reads / writes and reasoning subsets',()=>{
 function cost(model,usage,tier='default'){return U.estimateCost({model,usage,serviceTier:tier}).estimatedUSD;}
 assert.ok(Math.abs(cost('gpt-6-luna',{input_tokens:8000,output_tokens:4000})-.0028)<1e-12);
 assert.ok(Math.abs(cost('gpt-6.1-sol',{input_tokens:8000,output_tokens:4000})-.056)<1e-12);
 assert.ok(Math.abs(cost('gpt-6-luna',{input_tokens:8000,output_tokens:4000,input_tokens_details:{cached_tokens:2000,cache_write_tokens:1000},output_tokens_details:{reasoning_tokens:1500}})-.002645)<1e-12);
 assert.equal(cost('unknown',{input_tokens:10,output_tokens:10}),null);assert.equal(cost('gpt-6-luna',{input_tokens:10,output_tokens:10},'unpriced-tier'),null);
 assert.ok(Math.abs(cost('gpt-6-luna',{input_tokens:273000,output_tokens:1000})-.05535)<1e-12);
});
test('WSH compatibility uses the actual shared aggregation and cost code',()=>{const root=path.resolve(__dirname,'..'),box=vm.createContext({});vm.runInContext('JSON=undefined;Object.keys=undefined;Array.prototype.indexOf=undefined;',box);vm.runInContext(fs.readFileSync(path.join(root,'core','json_compat.js'),'utf8'),box);vm.runInContext(fs.readFileSync(path.join(root,'core','usage.js'),'utf8'),box);const req={events:[event('a'),event('b')],today:'2026-10-14',days:30};box.input=JSON.stringify(req);assert.deepEqual(JSON.parse(vm.runInContext('JSON.stringify(UsageEngine.summarize(JSON.parse(input)))',box)),U.summarize(req));});
test('late pending and older priced events cannot erase confirmed usage',()=>{
 const e=event('a','2026-10-14',{updatedAtUtc:'2026-10-14T04:00:00Z'});
 const r=sum([e,{...e,status:'pending',usageKnown:false,estimatedUSD:null},{...e,updatedAtUtc:'2026-10-14T03:00:00Z',inputTokens:1}]);
 assert.equal(r.totals.totalTokens,12000);assert.equal(r.totals.knownCalls,1);
});
test('cache and reasoning details have identical bounds in rows and totals',()=>{
 const r=sum([event('a','2026-10-14',{cachedTokens:7000,cacheWriteTokens:5000,reasoningTokens:9000})]);
 assert.equal(r.totals.cacheWriteTokens,1000);assert.equal(r.calls[0].CacheWrite,r.totals.cacheWriteTokens);assert.equal(r.calls[0].Reasoning,4000);
 const unknown=U.estimateCost({model:'unknown',searchCalls:2});assert.equal(unknown.estimatedUSD,null);assert.equal(unknown.searchUSD,.02);
});
test('completed run cannot regress to a late cancellation or export checkpoint',()=>{
 const e=event('end','2026-10-14',{kind:'run_result',runId:'r',status:'completed',generatedCount:24});
 const r=sum([e,{...e,status:'cancelled',generatedCount:12},{...e,status:'exporting',generatedCount:2}]);
 assert.equal(r.totals.generatedPresets,24);assert.equal(r.totals.completedRuns,1);
});
console.log(`${passed} usage tests passed`);
