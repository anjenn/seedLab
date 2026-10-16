/* Minimal strict JSON codec for Windows Script Host. Never evaluates input. */
if(typeof JSON==='undefined')JSON={};
if(!JSON.parse)JSON.parse=function(text){
 var at=0,ch=' ',s=String(text);
 function error(){throw new Error('Invalid JSON at '+at);}
 function next(c){if(c && c!==ch)error();ch=s.charAt(at++);return ch;}
 function white(){while(ch && ch<=' ')next();}
 function string(){var r='',u,i,e={b:'\b',f:'\f',n:'\n',r:'\r',t:'\t','"':'"','\\':'\\','/':'/'};next('"');
  while(ch){if(ch==='"'){next();return r;}if(ch==='\\'){next();if(ch==='u'){u='';for(i=0;i<4;i++){next();if(!/[0-9a-f]/i.test(ch))error();u+=ch;}r+=String.fromCharCode(parseInt(u,16));next();}else{if(!Object.prototype.hasOwnProperty.call(e,ch))error();r+=e[ch];next();}}else{if(ch<' ')error();r+=ch;next();}}error();}
 function value(){white();var r,k,n,st;
  if(ch==='"')return string();
  if(ch==='['){r=[];next('[');white();if(ch===']'){next();return r;}while(ch){r.push(value());white();if(ch===']'){next();return r;}next(',');}error();}
  if(ch==='{'){r={};next('{');white();if(ch==='}'){next();return r;}while(ch){white();if(ch!=='"')error();k=string();if(k==='__proto__'||k==='constructor'||k==='prototype')error();white();next(':');r[k]=value();white();if(ch==='}'){next();return r;}next(',');}error();}
  if(ch==='t'){next('t');next('r');next('u');next('e');return true;}
  if(ch==='f'){next('f');next('a');next('l');next('s');next('e');return false;}
  if(ch==='n'){next('n');next('u');next('l');next('l');return null;}
  st=at-1;n=/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/.exec(s.slice(st));if(!n)error();at=st+n[0].length;next();r=Number(n[0]);if(!isFinite(r))error();return r;
 }
 var result=value();white();if(ch)error();return result;
};
if(!JSON.stringify)JSON.stringify=function(o){
 function quote(s){return '"'+String(s).replace(/[\\"\x00-\x1f]/g,function(c){var e={'"':'\\"','\\':'\\\\','\b':'\\b','\f':'\\f','\n':'\\n','\r':'\\r','\t':'\\t'};return e[c]||'\\u'+('0000'+c.charCodeAt(0).toString(16)).slice(-4);})+'"';}
 function enc(v){var a=[],k,i,t=typeof v;if(v===null)return 'null';if(t==='string')return quote(v);if(t==='boolean')return String(v);if(t==='number')return isFinite(v)?String(v):'null';if(Object.prototype.toString.call(v)==='[object Array]'){for(i=0;i<v.length;i++)a.push(enc(v[i])||'null');return '['+a.join(',')+']';}if(t==='object'){for(k in v)if(Object.prototype.hasOwnProperty.call(v,k)&&typeof v[k]!=='undefined')a.push(quote(k)+':'+enc(v[k]));return '{'+a.join(',')+'}';}return undefined;}
 return enc(o);
};
// Older WSH versions lack Array#indexOf.
if(!Array.prototype.indexOf)Array.prototype.indexOf=function(v){for(var i=0;i<this.length;i++)if(this[i]===v)return i;return -1;};
