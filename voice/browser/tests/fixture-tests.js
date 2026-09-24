const sandbox=document.querySelector('#sandbox'),out=document.querySelector('#results');
const request=(op,rest={})=>LocalVoiceDOM.run({op,expectedURL:location.href,deadline:Date.now()+2000,...rest});
const assert=(condition,message='Assertion failed')=>{if(!condition)throw Error(message);};
const results=[];
function fixture(html){sandbox.innerHTML=html;}
function test(name,fn){try{fn();results.push({name,ok:true});}catch(error){results.push({name,ok:false,error:error.message});}}
document.querySelector('#run').onclick=()=>{
 results.length=0;
 test('Label-based fill with input event',()=>{fixture('<label>Destination<input></label>');let events=0;sandbox.querySelector('input').oninput=()=>events++;assert(request('fill',{target:'destination',value:'Oslo'}).ok);assert(sandbox.querySelector('input').value==='Oslo'&&events===1);});
 test('aria-labelledby control',()=>{fixture('<span id="caption">Organization</span><input aria-labelledby="caption">');assert(request('fill',{target:'Organization',value:'Example'}).ok);});
 test('Placeholder matching',()=>{fixture('<input placeholder="Find a book">');assert(request('fill',{target:'find a book',value:'Invisible Cities'}).ok);});
 test('Native select',()=>{fixture('<label>Region<select><option>Japan</option><option>Canada</option></select></label>');assert(request('select',{target:'Region',value:'Canada'}).ok);assert(sandbox.querySelector('select').selectedOptions[0].text==='Canada');});
 test('Checkbox is idempotent',()=>{fixture('<label><input type="checkbox">Email updates</label>');assert(request('check',{target:'Email updates',checked:true}).ok);assert(request('check',{target:'Email updates',checked:true}).ok);assert(sandbox.querySelector('input').checked);assert(request('check',{target:'Email updates',checked:false}).ok);});
 test('Button click observed',()=>{fixture('<button>Show details</button><output></output>');sandbox.querySelector('button').onclick=()=>sandbox.querySelector('output').textContent='Details shown';assert(request('click',{target:'Show details'}).ok);assert(sandbox.querySelector('output').textContent==='Details shown');});
 test('Ambiguous name abstains',()=>{fixture('<button>Continue</button><button>Continue</button>');assert(!request('click',{target:'Continue'}).ok);});
 test('Disabled and hidden controls excluded',()=>{fixture('<button disabled>Continue</button><button hidden>Continue</button><button id="good">Continue</button>');let count=0;sandbox.querySelector('#good').onclick=()=>count++;assert(request('click',{target:'Continue'}).ok);assert(count===1);});
 test('Password cannot be filled',()=>{fixture('<input type="password" aria-label="Password">');assert(!request('fill',{target:'Password',value:'not-a-real-password'}).ok);});
 test('DOM mutation invalidates index',()=>{fixture('<button>Old name</button>');assert(request('click',{target:'Old name'}).ok);sandbox.querySelector('button').textContent='New name';assert(request('click',{target:'New name'}).ok);assert(!request('click',{target:'Old name'}).ok);});
 test('Open shadow DOM',()=>{fixture('<div id="host"></div>');sandbox.querySelector('#host').attachShadow({mode:'open'}).innerHTML='<input aria-label="Nickname">';assert(request('fill',{target:'Nickname',value:'River'}).ok);});
 test('Generic search form',()=>{fixture('<form role="search"><input type="search" aria-label="Search catalog"><button>Search</button></form>');let submitted='';sandbox.querySelector('form').onsubmit=e=>{e.preventDefault();submitted=e.target.querySelector('input').value;};assert(request('search',{value:'wooden toys'}).ok);assert(submitted==='wooden toys');});
 test('Multiple searches abstain',()=>{fixture('<input type="search"><input type="search">');assert(!request('search',{value:'test'}).ok);});
 test('Type inserts at selection',()=>{fixture('<textarea aria-label="Message">Hello friend</textarea>');const el=sandbox.querySelector('textarea');el.focus();el.setSelectionRange(6,12);assert(request('type',{value:'world'}).ok);assert(el.value==='Hello world');});
 test('Send requires unchanged dictated draft',()=>{fixture('<form><textarea></textarea><button>Send</button></form>');let sent=0;sandbox.querySelector('form').onsubmit=e=>{e.preventDefault();sent++;};const el=sandbox.querySelector('textarea');el.focus();assert(request('type',{value:'Draft only'}).ok);assert(sent===0);assert(request('send').ok);assert(sent===1);assert(!request('send').ok);});
 test('Changed draft blocks send',()=>{fixture('<textarea></textarea><button>Send</button>');const el=sandbox.querySelector('textarea');el.focus();assert(request('type',{value:'First'}).ok);el.value='Edited';assert(!request('send').ok);});
 test('Expired commands never click',()=>{fixture('<button>Continue</button>');let count=0;sandbox.querySelector('button').onclick=()=>count++;assert(!request('click',{target:'Continue',deadline:0}).ok);assert(count===0);});
 test('Changed URL never clicks',()=>{fixture('<button>Continue</button>');assert(!request('click',{target:'Continue',expectedURL:'https://other.invalid/'}).ok);});
 fixture('<label>Benchmark field<input></label>');
 const times=[];
 for(let i=0;i<220;i++){const result=request('fill',{target:'Benchmark field',value:`Value ${i}`});if(i>=20)times.push(result.domMs);}
 times.sort((a,b)=>a-b);
 const report={passed:results.filter(x=>x.ok).length,total:results.length,results,domWarmMs:{median:times[100],p95:times[190]},note:'Real browser DOM only; excludes Swift/native messaging and speech.'};
 out.textContent=`${report.passed}/${report.total} passed; DOM median ${report.domWarmMs.median.toFixed(3)} ms; p95 ${report.domWarmMs.p95.toFixed(3)} ms\n`+JSON.stringify(report,null,2);
 fixture('<form role="search"><label>Search catalog<input type="search"></label><button>Search</button><output></output></form><label>Country<select><option>Japan</option><option>Canada</option></select></label><label><input type="checkbox">Email updates</label><button id="details">Show details</button><p id="detail-result"></p>');
 sandbox.querySelector('form').onsubmit=e=>{e.preventDefault();sandbox.querySelector('output').textContent='Results for '+sandbox.querySelector('input').value;};
 sandbox.querySelector('#details').onclick=()=>document.querySelector('#detail-result').textContent='Details are visible';
};
