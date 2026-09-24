// Named-container targeting in disposable offline Chrome. No personal UI or network.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {Headless}=require('./headless.cjs');
const args=process.argv.slice(2),output=args.includes('--output')?args[args.indexOf('--output')+1]:null;
if(output&&fs.existsSync(output))throw Error('Use a new output path');
const controller=path.join(__dirname,'../extension/controller.js'),source=fs.readFileSync(controller,'utf8');
const hash=s=>crypto.createHash('sha256').update(s).digest('hex');
const button=id=>`<button id="${id}" type="button" aria-pressed="false">Save</button>`;
const field=(id,value='old')=>`<label>Email<input id="${id}" value="${value}"></label>`;
const section=(id,name,body)=>`<section id="${id}" aria-label="${name}">${body}</section>`;
const buttons=()=>section('profile','Profile',button('intended'))+section('billing','Billing',button('other'));
const fields=()=>section('profile','Profile',field('intended','Oslo'))+section('billing','Billing',field('other','Kyoto'));
const scopedClick={op:'click',target:'Save button in the Profile section'};
const cases=[
 {name:'named section selects one repeated button',html:buttons(),request:scopedClick,bound:true,outcome:'verified',clicks:1,check:"counts.intended===1&&!counts.other"},
 {name:'direct named click uses same scope',html:buttons(),request:scopedClick,outcome:'verified',clicks:1,check:"counts.intended===1&&!counts.other"},
 {name:'heading names a section',html:'<section><h2>Profile</h2>'+button('intended')+'</section>'+section('billing','Billing',button('other')),request:scopedClick,outcome:'verified',clicks:1,check:"counts.intended===1&&!counts.other"},
 {name:'ARIA labelledby names a region',html:'<h2 id="caption">Profile</h2><div role="region" aria-labelledby="caption">'+button('intended')+'</div>'+section('billing','Billing',button('other')),request:scopedClick,bound:true,outcome:'verified',clicks:1,check:"counts.intended===1&&!counts.other"},
 {name:'named form disambiguates duplicate fields',html:'<form aria-label="Billing">'+field('intended')+'</form><form aria-label="Shipping">'+field('other')+'</form>',request:{op:'fill',target:'Email in the Billing form',value:'local@example.test'},outcome:'verified',inputs:1,check:"intended.value==='local@example.test'&&other.value==='old'"},
 {name:'fieldset legend names a group',html:'<fieldset><legend>Billing</legend><label><input id="intended" type="checkbox">Updates</label></fieldset><fieldset><legend>Shipping</legend><label><input id="other" type="checkbox">Updates</label></fieldset>',request:{op:'check',target:'Updates in Billing group',checked:true},outcome:'verified',clicks:0,inputs:1,check:'intended.checked&&!other.checked'},
 {name:'select options in a named section',html:section('shipping','Shipping','<label>Country<select id="intended"><option>France</option><option>Canada</option></select></label>')+section('billing','Billing','<label>Country<select id="other"><option>France</option><option>Canada</option></select></label>'),request:{op:'select',target:'Country in Shipping section',value:'Canada'},outcome:'verified',inputs:1,check:"intended.value==='Canada'&&other.value==='France'"},
 {name:'copy resolves source and destination sections',html:fields(),request:{op:'copyText',source:'Email in Profile section',target:'Email in Billing section'},outcome:'verified',inputs:1,check:"intended.value==='Oslo'&&other.value==='Oslo'"},
 {name:'case change targets one repeated field',html:fields(),request:{op:'changeCase',target:'Email in Billing section',value:'uppercase'},outcome:'verified',inputs:1,check:"intended.value==='Oslo'&&other.value==='KYOTO'"},
 {name:'open shadow root resolves its own scope label',html:'<div id="host"></div>'+section('billing','Billing',button('other')),setup:`host.attachShadow({mode:'open'}).innerHTML='<h2 id="caption">Profile</h2><section aria-labelledby="caption">${button('intended')}</section>';`,request:scopedClick,bound:true,outcome:'verified',clicks:1,check:"counts.intended===1&&!counts.other"},
 {name:'unqualified repeated label still rejects',html:buttons(),request:{op:'click',target:'Save'},outcome:'failed',check:'!counts.intended&&!counts.other'},
 {name:'duplicate scope names reject',html:buttons()+section('duplicate','Profile',button('third')),request:scopedClick,outcome:'failed',check:'!counts.intended&&!counts.other&&!counts.third'},
 {name:'duplicate target inside selected scope rejects',html:section('profile','Profile',button('intended')+button('second')),request:scopedClick,outcome:'failed',check:'!counts.intended&&!counts.second'},
 {name:'missing scope does not fall back to global target',html:button('intended'),request:scopedClick,outcome:'failed',check:'!counts.intended'},
 {name:'hidden scope is not available',html:buttons(),setup:'profile.hidden=true',request:scopedClick,outcome:'failed',check:'!counts.intended&&!counts.other'},
 {name:'disabled scope is not available',html:buttons(),setup:"profile.setAttribute('aria-disabled','true')",request:scopedClick,outcome:'failed',check:'!counts.intended&&!counts.other'},
 {name:'scope cannot escape active modal',html:buttons()+'<dialog id="modal" aria-label="Confirmation">'+button('dialogButton')+'</dialog>',setup:'modal.showModal()',request:scopedClick,outcome:'failed',check:'!counts.intended&&!counts.dialogButton'},
 {name:'named active dialog is usable',html:buttons()+'<dialog id="modal" aria-label="Confirmation">'+button('dialogButton')+'</dialog>',setup:'modal.showModal()',request:{op:'click',target:'Save in Confirmation dialog'},bound:true,outcome:'verified',clicks:1,check:'counts.dialogButton===1&&!counts.intended'},
 {name:'ordinary sign in label remains literal',html:'<button id="intended" aria-pressed="false">Sign in</button>',request:{op:'click',target:'Sign in'},outcome:'verified',clicks:1,check:'counts.intended===1'},
 {name:'literal label containing scope words remains usable',html:'<button id="intended" aria-pressed="false">Open in side panel</button>',request:{op:'click',target:'Open in side panel'},outcome:'verified',clicks:1,check:'counts.intended===1'},
 {name:'literal and scoped interpretations cannot choose different buttons',html:'<button id="literal" aria-pressed="false">Open in side panel</button>'+section('side','Side','<button id="intended" aria-pressed="false">Open</button>'),request:{op:'click',target:'Open in side panel'},outcome:'failed',check:'!counts.intended&&!counts.literal'},
 {name:'bare in phrase is not silently treated as scope',html:buttons(),request:{op:'click',target:'Save in Profile'},outcome:'failed',check:'!counts.intended'},
 {name:'renamed scope invalidates bound observation',html:buttons(),request:scopedClick,bound:true,before:"profile.setAttribute('aria-label','Account')",outcome:'failed',check:'!counts.intended'},
 {name:'replacement scope invalidates bound observation',html:buttons(),request:scopedClick,bound:true,before:"const replacement=profile.cloneNode(false);replacement.append(intended);profile.replaceWith(replacement)",outcome:'failed',check:'!counts.intended'},
 {name:'new matching target invalidates bound choice',html:buttons(),request:scopedClick,bound:true,before:"profile.insertAdjacentHTML('beforeend','<button>Save</button>')",outcome:'failed',check:'!counts.intended'},
 {name:'focus-time scope change prevents text input',html:fields(),setup:"intended.onfocus=()=>profile.setAttribute('aria-label','Moved')",request:{op:'fill',target:'Email in Profile section',value:'new'},outcome:'failed',check:"intended.value==='Oslo'&&other.value==='Kyoto'"},
 {name:'moving field to a different same-name scope before input refuses',html:fields(),setup:"intended.onfocus=()=>{intended.onfocus=null;const replacement=profile.cloneNode(false);replacement.append(...profile.childNodes);profile.replaceWith(replacement);intended.focus()}",request:{op:'fill',target:'Email in Profile section',value:'new'},outcome:'failed',check:"intended.value==='Oslo'&&other.value==='Kyoto'"},
 {name:'post-input scope change is unverified and not retried',html:fields(),setup:"intended.oninput=()=>profile.setAttribute('aria-label','Moved')",request:{op:'fill',target:'Email in Profile section',value:'new'},outcome:'unverified',inputs:1,check:"intended.value==='new'&&other.value==='Kyoto'"},
 {name:'moving field to a different same-name scope after input is unverified',html:fields(),setup:"intended.oninput=()=>{intended.oninput=null;const replacement=profile.cloneNode(false);replacement.append(...profile.childNodes);profile.replaceWith(replacement);intended.focus()}",request:{op:'fill',target:'Email in Profile section',value:'new'},outcome:'unverified',inputs:1,check:"intended.value==='new'&&other.value==='Kyoto'"},
 {name:'copy cannot follow a destination moved to a replacement scope',html:fields(),setup:"other.onfocus=()=>{other.onfocus=null;const replacement=billing.cloneNode(false);replacement.append(...billing.childNodes);billing.replaceWith(replacement);other.focus()}",request:{op:'copyText',source:'Email in Profile section',target:'Email in Billing section'},outcome:'failed',check:"intended.value==='Oslo'&&other.value==='Kyoto'"},
 {name:'multiple direct headings do not invent a scope name',html:'<section><h2>Profile</h2><h2>Billing</h2>'+button('intended')+'</section>',request:scopedClick,outcome:'failed',check:'!counts.intended'},
 {name:'duplicate labelledby IDs cannot name a scope',html:'<h2 id="caption">Profile</h2><h2 id="caption">Profile</h2><section aria-labelledby="caption">'+button('intended')+'</section>',request:scopedClick,outcome:'failed',check:'!counts.intended'},
];
(async()=>{const b=new Headless({virtualTime:true}),rows=[];try {
 await b.start();
 for(const c of cases) {
  await b.evaluate(`(()=>{document.body.innerHTML=${JSON.stringify('<style>section,fieldset,form{padding:10px;margin:8px;border:1px solid #aaa}button,input,select{margin:8px}</style>'+c.html)};globalThis.counts={};globalThis.inputs=0;globalThis.submits=0;${c.setup||''};
   const roots=[document,...[...document.querySelectorAll('*')].map(e=>e.shadowRoot).filter(Boolean)];
   for(const root of roots)for(const button of root.querySelectorAll('button'))button.addEventListener('click',()=>{counts[button.id]=(counts[button.id]||0)+1;button.setAttribute('aria-pressed','true')});
   document.body.oninput=()=>inputs++;document.body.onsubmit=e=>{submits++;e.preventDefault()};})()`);
  await b.controller(source);
  let request=c.request,observed=true;
  if(c.bound) {
   const reply=await b.run('observe',{target:c.request.target}),observation=reply.observation;
   observed=!!observation&&!observation.truncated&&observation.candidates.length===1;
   if(observed)request={...request,targetId:observation.candidates[0].id,documentId:observation.documentId,observationId:observation.observationId};
  }
  if(c.before&&observed)await b.evaluate(c.before);
  const result=observed?await b.run(request.op,request):{outcome:'fixture-no-target'};
  const effects=await b.evaluate(`({counts,inputs,submits,correct:!!(${c.check})})`);
  const clicks=Object.values(effects.counts).reduce((a,b)=>a+b,0);
  rows.push({name:c.name,passed:observed&&result.outcome===c.outcome&&effects.correct&&clicks===(c.clicks??0)&&effects.inputs===(c.inputs??0)&&effects.submits===0,expectedOutcome:c.outcome,result,effects});
 }
 const report={scope:'Production DOM controller in isolated offline headless Chrome; generated fixtures and independent actual effects. No speech/native host, live sites, user tabs or end-to-end latency claim.',clock:'virtual time',controllerSHA256:hash(source),testSHA256:hash(fs.readFileSync(__filename)),sourceChangedDuringRun:hash(source)!==hash(fs.readFileSync(controller)),browser:b.version.product,passed:rows.filter(r=>r.passed).length,total:rows.length,rows};
 if(output)fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({passed:report.passed,total:report.total,failures:rows.filter(r=>!r.passed)}));
 if(report.passed!==report.total||report.sourceChangedDuringRun)process.exitCode=1;
}finally{await b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
