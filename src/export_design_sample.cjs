// Extract the self-authored preview's deterministic sample ledger.
// No browser, network, API call, or user usage records are used.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'DesignPreview.html'),'utf8');
const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);
const sample=scripts[scripts.length-1].split('function draw()')[0];
const context={document:{getElementById:()=>null},UsageEngine:require('../usage.js'),console};
vm.createContext(context);
const result=vm.runInContext(sample+"\nUsageEngine.summarize({events,today,days:7,model:'all'})",context);
fs.writeFileSync(process.argv[2],JSON.stringify(result,null,2)+'\n');
