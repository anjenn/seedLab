// Windows Script Host only; input and output are UTF-8 JSON files.
function readText(path){var s=new ActiveXObject('ADODB.Stream');s.Type=2;s.Charset='utf-8';s.Open();s.LoadFromFile(path);var t=s.ReadText();s.Close();return t.replace(/^\uFEFF/,'');}
function writeText(path,text){var s=new ActiveXObject('ADODB.Stream');s.Type=2;s.Charset='utf-8';s.Open();s.WriteText(text);s.SaveToFile(path,2);s.Close();}
var fso=new ActiveXObject('Scripting.FileSystemObject'),folder=fso.GetParentFolderName(WScript.ScriptFullName);
try {
// Only bundled code is executed; JSON from presets and the API uses a strict parser.
eval(readText(fso.BuildPath(folder,'json_compat.js')));
eval(readText(fso.BuildPath(folder,'engine.js')));
eval(readText(fso.BuildPath(folder,'usage.js')));
eval(readText(fso.BuildPath(folder,'reference.js')));
var req=JSON.parse(readText(WScript.Arguments(0)));var result=req.operation==='reference_schema'?ReferenceEngine.contract():req.operation==='reference_observations'?ReferenceEngine.validateObservations(req):req.operation==='reference_recipes'?ReferenceEngine.validateRecipes(req):req.operation==='reference_generate'?ReferenceEngine.generate(req):req.operation==='research_meta'?ReferenceEngine.researchMeta(req):req.operation==='usage'?UsageEngine.summarize(req):req.operation==='cost'?UsageEngine.estimateCost(req):req.operation==='prepare'?SeedEngine.prepare(req):SeedEngine.generate(req);writeText(WScript.Arguments(1),JSON.stringify(result));}
catch(e){writeText(WScript.Arguments(1),JSON.stringify({error:String(e.message||e)}));WScript.Quit(1);}
