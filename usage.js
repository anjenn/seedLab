/* ES5 usage aggregation for the native dashboard and its tests. */
(function(root){
 'use strict';
 function own(o,k){return Object.prototype.hasOwnProperty.call(o,k);}
 function number(v){return typeof v==='number' && isFinite(v) && v>=0;}
 function date(s){if(!/^\d{4}-\d{2}-\d{2}$/.test(s||''))return null;var p=s.split('-'),d=new Date(Date.UTC(+p[0],+p[1]-1,+p[2]));return key(d)===s?d:null;}
 function key(d){function pad(n){return ('0'+n).slice(-2);}return d.getUTCFullYear()+'-'+pad(d.getUTCMonth()+1)+'-'+pad(d.getUTCDate());}
 function shift(s,n){var d=date(s);d.setUTCDate(d.getUTCDate()+n);return key(d);}
 function blank(){return {inputTokens:0,outputTokens:0,totalTokens:0,cachedTokens:0,cacheWriteTokens:0,reasoningTokens:0,webSearchCalls:0,searchUSD:0,calls:0,knownCalls:0,unknownCalls:0,failedCalls:0,runs:0,referenceRuns:0,completedRuns:0,generatedPresets:0,estimatedUSD:0,costUnknownCalls:0};}
 function known(e){return e.usageKnown===true && number(e.inputTokens)&&number(e.outputTokens);}
 function cached(e){return Math.min(e.inputTokens,number(e.cachedTokens)?e.cachedTokens:0);}
 function writes(e){return Math.min(e.inputTokens-cached(e),number(e.cacheWriteTokens)?e.cacheWriteTokens:0);}
 function reasoning(e){return Math.min(e.outputTokens,number(e.reasoningTokens)?e.reasoningTokens:0);}
 function estimateCost(req){
  var rates={'gpt-6-luna':[.10,.01,.125,.50],'gpt-6.1-sol':[2,.10,2.50,10]},u=req.usage,t=req.serviceTier;
  var searches=req.searchCalls===undefined?0:req.searchCalls;
  if(!number(searches)||Math.floor(searches)!==searches)return {estimatedUSD:null};
  if(!u||!own(rates,req.model)||(t&&t!=='default'&&t!=='standard')||!number(u.input_tokens)||!number(u.output_tokens))return {estimatedUSD:null,tokenUSD:null,searchUSD:searches*.01};
  var details=u.input_tokens_details||{},input=u.input_tokens,output=u.output_tokens,cached=Math.min(input,number(details.cached_tokens)?details.cached_tokens:0),writes=Math.min(input-cached,number(details.cache_write_tokens)?details.cache_write_tokens:0);
  var rate=rates[req.model],inf=input>272000?2:1,outf=input>272000?1.5:1;
  var tokenUSD=((input-cached-writes)*rate[0]*inf+cached*rate[1]*inf+writes*rate[2]*inf+output*rate[3]*outf)/1000000,searchUSD=searches*.01;
  return {estimatedUSD:tokenUSD+searchUSD,tokenUSD:tokenUSD,searchUSD:searchUSD};
 }
 function summarize(req){
  var today=req.today;if(!date(today))throw new Error('Invalid dashboard date');
  var dedup={},list=[],events=req.events||[],i,e,id,discarded=0;
  for(i=0;i<events.length;i++){
   e=events[i];if(!e||typeof e.eventId!=='string'||!e.eventId||!date(e.localDate)||['api','run_start','run_result'].indexOf(e.kind)<0){discarded++;continue;}
   // Duplicate or delayed lifecycle events cannot erase already confirmed usage.
   var prior=dedup['id:'+e.eventId];
   if(prior){
    if(e.kind==='api'&&known(prior)&&!known(e))continue;
    if(e.kind==='run_result'&&(prior.status==='completed'||((prior.status==='cancelled'||prior.status==='failed')&&e.status==='exporting')))continue;
    if(String(prior.updatedAtUtc||prior.timestampUtc||'')>String(e.updatedAtUtc||e.timestampUtc||''))continue;
   }
   dedup['id:'+e.eventId]=e;
  }
  for(id in dedup)if(own(dedup,id))list.push(dedup[id]);
  list.sort(function(a,b){return String(a.timestampUtc||'').localeCompare(String(b.timestampUtc||''));});
  var days=req.days==='all'?'all':Math.floor(Number(req.days)||30);if(days!=='all'&&(days<1||days>3660))throw new Error('Invalid range');
  var earliest=today;
  for(i=0;i<list.length;i++)if(list[i].localDate<earliest)earliest=list[i].localDate;
  var start=days==='all'?earliest:shift(today,1-days),previousStart=days==='all'?null:shift(start,-days),previousEnd=shift(start,-1);
  var total=blank(),previous=blank(),daily={},models={},rows=[],runRows=[],runMap={},allModels={},modelFilter=req.model||'all';
  function modelOf(e){return String(e.model||'local');}
  function addCall(target,e){
   target.calls++;
   target.webSearchCalls+=number(e.webSearchCalls)?e.webSearchCalls:0;
   target.searchUSD+=number(e.searchUSD)?e.searchUSD:0;
   if(e.status==='failed'||e.status==='incomplete'||e.status==='refused')target.failedCalls++;
   if(!known(e)){target.unknownCalls++;target.costUnknownCalls++;return;}
   target.knownCalls++;target.inputTokens+=e.inputTokens;target.outputTokens+=e.outputTokens;target.totalTokens+=e.inputTokens+e.outputTokens;
   target.cachedTokens+=cached(e);
   target.cacheWriteTokens+=writes(e);
   target.reasoningTokens+=reasoning(e);
   if(number(e.estimatedUSD))target.estimatedUSD+=e.estimatedUSD;else target.costUnknownCalls++;
  }
  function dayOf(s){if(!daily[s]){daily[s]=blank();daily[s].date=s;}return daily[s];}
  function modelStats(m){var mk='m:'+m;if(!models[mk]){models[mk]=blank();models[mk].model=m;}return models[mk];}
  for(i=0;i<list.length;i++){
   e=list[i];var m=modelOf(e);if(e.kind==='api')allModels['m:'+m]=m;
   if(modelFilter!=='all'&&m!==modelFilter)continue;
   if(e.localDate>today)continue;
   if(e.kind==='run_start'){if(!runMap['r:'+e.runId])runMap['r:'+e.runId]={};runMap['r:'+e.runId].start=e;continue;}
   if(e.kind==='run_result'){
    var rk='r:'+e.runId;if(!runMap[rk])runMap[rk]={};runMap[rk].result=e;continue;
   }
   if(e.localDate<start){if(previousStart&&e.localDate>=previousStart&&e.localDate<=previousEnd)addCall(previous,e);continue;}
   addCall(total,e);addCall(dayOf(e.localDate),e);addCall(modelStats(m),e);
   rows.push({EventId:e.eventId,RunId:e.runId,Time:e.localTime||e.timestampUtc,Date:e.localDate,Model:m,
    Status:e.status==='completed'?'완료':e.status==='pending'?'응답 대기 / 미확인':e.status==='failed'?(known(e)?'실패':'실패 / 미확인'):e.status==='incomplete'?'응답 미완료':e.status==='refused'?'요청 거절':String(e.status||'미확인'),
    Input:known(e)?e.inputTokens:null,Output:known(e)?e.outputTokens:null,Total:known(e)?e.inputTokens+e.outputTokens:null,
    Cached:known(e)?cached(e):null,CacheWrite:known(e)?writes(e):null,
    Reasoning:known(e)?reasoning(e):null,
    USD:number(e.estimatedUSD)?e.estimatedUSD:null,SearchCalls:number(e.webSearchCalls)?e.webSearchCalls:0,SearchUSD:number(e.searchUSD)?e.searchUSD:null,Phase:e.phase||'seed_variation',Mode:e.mode||'seed',DurationMs:number(e.durationMs)?e.durationMs:null,UsageKnown:known(e),PriceDate:e.priceDate||'',Batch:e.batchIndex||0});
  }
  for(id in runMap)if(own(runMap,id)){
   var run=runMap[id],beg=run.start||run.result,end=run.result;
   if(beg.localDate<start||beg.localDate>today)continue;
   total.runs++;dayOf(beg.localDate).runs++;
   if(beg.mode==='reference'){total.referenceRuns++;dayOf(beg.localDate).referenceRuns++;}
   var count=end&&number(end.generatedCount)?end.generatedCount:0;
   total.generatedPresets+=count;dayOf(beg.localDate).generatedPresets+=count;
   if(end&&end.status==='completed'){total.completedRuns++;dayOf(beg.localDate).completedRuns++;}
   runRows.push({RunId:beg.runId,Time:beg.localTime||beg.timestampUtc,Model:modelOf(beg)==='local'?'로컬':modelOf(beg),
    Status:!end?'진행 중 / 종료 미확인':end.status==='completed'?'완료':end.status==='cancelled'?'중지':end.status==='exporting'?'내보내는 중':'실패',
    Requested:beg.requestedCount||0,Generated:count,Mode:beg.mode==='mix'?'믹스매치':beg.mode==='reference'?'레퍼런스':beg.mode==='local'?'로컬':'씨드',DurationMs:end&&number(end.durationMs)?end.durationMs:null,Folder:end?end.folder||'':''});
  }
  var d=start;while(d<=today){dayOf(d);d=shift(d,1);}
  var dailyList=[];for(id in daily)if(own(daily,id))dailyList.push(daily[id]);dailyList.sort(function(a,b){return a.date.localeCompare(b.date);});
  // Weekly buckets keep long ranges legible. Exact daily values remain in export.
  var chart=[],bucket;
  for(i=0;i<dailyList.length;i++){
   if(dailyList.length>31){if(i%7===0){bucket=blank();bucket.date=dailyList[i].date;bucket.endDate=dailyList[i].date;chart.push(bucket);}else bucket.endDate=dailyList[i].date;
    for(id in total)if(own(total,id)&&number(dailyList[i][id]))bucket[id]+=dailyList[i][id];
   }else chart.push(dailyList[i]);
  }
  var modelList=[];for(id in models)if(own(models,id))modelList.push(models[id]);modelList.sort(function(a,b){return b.totalTokens-a.totalTokens;});
  rows.sort(function(a,b){return String(b.Time).localeCompare(String(a.Time));});runRows.sort(function(a,b){return String(b.Time).localeCompare(String(a.Time));});
  var comparison=previous.totalTokens?Math.round((total.totalTokens-previous.totalTokens)/previous.totalTokens*100):null;
  var names=[];for(id in allModels)if(own(allModels,id))names.push(allModels[id]);
  return {totals:total,previous:previous,changePercent:comparison,start:start,end:today,chartUnit:dailyList.length>31?'주별':'일별',daily:dailyList,chart:chart,models:modelList,allModels:names,calls:rows,runs:runRows,discardedEvents:discarded};
 }
 function keys(o){var r=[],k;for(k in o)if(own(o,k))r.push(k);return r;}
 var api={summarize:summarize,estimateCost:estimateCost};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.UsageEngine=api;
}(this));
