// Runs the actual Swift sequence planner/executor against generated, network-blocked pages.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {spawn}=require('node:child_process'),{createInterface}=require('node:readline');
const {Headless}=require('./headless.cjs');
const controller=fs.readFileSync(path.join(__dirname,'../extension/controller.js'),'utf8');
const binary=process.env.VOICE_SEQUENCE_CHECK;
if(!binary)throw Error('Set VOICE_SEQUENCE_CHECK to the compiled browser_sequence_check.swift fixture adapter');
const details=`<details><summary onclick="events.push('details')">Details</summary><input id="message" aria-label="Message"></details>`;
const popover=`<button popovertarget="panel" onclick="events.push('filters')">Filters</button><div id="panel" popover><input id="message" aria-label="Message"></div>`;
const plain=`<button onclick="events.push('noop')">Details</button><input id="message" aria-label="Message">`;
const field=`<input id="message" aria-label="Message"><input id="other" aria-label="Other">`;
const cases=[
 {name:'delayed test transport starts before clock advances',text:'focus Message then type Hello',html:field,verified:2,events:[],value:'Hello',delayTransport:true},
 {name:'disclosure reveals field',text:'click Details then fill Message with Hello',html:details,verified:2,events:['details'],value:'Hello'},
 {name:'focus and literal tail',text:'focus Message then type Hello, then click Send!',html:field,verified:2,events:[],value:'Hello, then click Send!'},
 {name:'three steps through popover',text:'click Filters then focus Message then type Hello',html:popover,verified:3,events:['filters'],value:'Hello'},
 {name:'exact click field then type',text:'click Message field then type Hello',html:field,verified:2,events:[],value:'Hello'},
 {name:'named region with duplicate field',text:'click Details then fill Message in Billing form with Hello',html:details+'<form aria-label="Billing"><input id="billing" aria-label="Message"></form>',verified:2,events:['details'],value:'',extra:"document.querySelector('#billing').value==='Hello'"},
 {name:'checkbox reveals field',text:'check Filters then fill Message with Hello',html:`<label><input type="checkbox" onclick="events.push('check');document.querySelector('#message').hidden=false">Filters</label><input id="message" hidden aria-label="Message">`,verified:2,events:['check'],value:'Hello'},
 {name:'native select followed by check',text:'select Blue from Color then check Filters',html:`<select aria-label="Color" onchange="events.push(this.value)"><option>Red</option><option>Blue</option></select><label><input type="checkbox" onclick="events.push('check')">Filters</label>`,verified:2,events:['Blue','check']},
 {name:'exact and conjunction',text:'check Filters and click Details',html:`<label><input type="checkbox" onclick="events.push('check')">Filters</label><details><summary onclick="events.push('details')">Details</summary>Visible</details>`,verified:2,events:['check','details']},
 {name:'unverified click stops before fill',text:'click Details then fill Message with Hello',html:plain,error:'step 1',events:['noop'],value:''},
 {name:'missing later field',text:'click Details then fill Missing with Hello',html:details,error:'step 2',events:['details'],value:''},
 {name:'duplicate later field',text:'click Details then fill Message with Hello',html:details+'<input aria-label="Message">',error:'step 2',events:['details'],value:''},
 {name:'protected field never receives text',text:'click Details then fill Password with Hello',html:details+'<input type="password" id="secret" aria-label="Password">',error:'step 2',events:['details'],value:'',extra:"document.querySelector('#secret').value===''"},
 {name:'unsupported submission preflight',text:'click Details then send it',html:details,error:'separate utterance',events:[],value:''},
 {name:'unsupported later operation model abstains',text:'click Details then delete Account',html:details,error:'unsupported',events:[],value:'',modelCalls:1},
 {name:'search must be separate',text:'click Details then search this site for cats',html:details,error:'separate utterance',events:[],value:''},
 {name:'page replaced after verified step',text:'click Details then fill Message with Hello',html:details,error:'Page changed',events:['details'],value:'',replaceAt:2},
 {name:'focus stolen before typing',text:'focus Message then type Hello',html:field,error:'lost focus',events:[],value:'',hook:[3,"document.querySelector('#other').focus()"]},
 {name:'field replaced before later step',text:'focus Message then type Hello',html:field,error:'lost focus',events:[],value:'',hook:[3,"document.querySelector('#message').outerHTML='<input id=message aria-label=Message>';document.querySelector('#message').focus()"]},
 {name:'replacement between binding and dispatch',text:'click Details then fill Message with Hello',html:details,error:'step 2',events:['details'],value:'',beforeSecondDispatch:"document.querySelector('#message').outerHTML='<input id=message aria-label=Message>'"},
 {name:'readonly field fails without text',text:'click Details then fill Message with Hello',html:details.replace('id="message"','readonly id="message"'),error:'step 2',events:['details'],value:''},
 {name:'large page uses filtered target observations',text:'click Details then fill Message with Hello',html:details+Array.from({length:60},(_,i)=>`<button>Control ${i}</button>`).join(''),verified:2,events:['details'],value:'Hello'},
 {name:'copy text after disclosure',text:'click Details then copy text from Source to Message',html:details+'<input aria-label="Source" value="Copied">',verified:2,events:['details'],value:'Copied'},
 {name:'case change after disclosure',text:'click Details then uppercase Message',html:details.replace('aria-label="Message"','aria-label="Message" value="hello"'),verified:2,events:['details'],value:'HELLO'},
 {name:'reverted first text edit blocks later checkbox',text:'uppercase Message then check Filters',html:`<input id="message" aria-label="Message" value="hello" oninput="setTimeout(()=>this.value='hello',60)"><label><input type="checkbox" onclick="events.push('check')">Filters</label>`,error:'step 1',events:[],value:'hello',writes:1},
 {name:'scroll followed by fill',text:'scroll down then fill Message with Hello',html:`<div style="height:4000px"></div><input id="message" aria-label="Message" style="position:fixed;top:10px;left:10px">`,verified:2,events:[],value:'Hello'},
 {name:'scroll at boundary stops before text',text:'scroll down then fill Message with Hello',html:field,error:'step 1',events:[],value:''},
 {name:'changed document blocks named text dispatch',text:'check Filters then uppercase Message',html:`<input id="message" aria-label="Message" value="hello"><label><input type="checkbox" onclick="events.push('check')">Filters</label>`,error:'step 2',events:['check'],value:'hello',replaceBeforeDispatch:2},
 {name:'typed checkbox reveals field among homonyms',text:'click Filters checkbox then fill Message with Hello',html:`<label><input type="checkbox" onclick="events.push('check');document.querySelector('#message').hidden=false">Filters</label><div role="link" tabindex="0" onclick="events.push('wrong')">Filters</div><input id="message" hidden aria-label="Message">`,verified:2,events:['check'],value:'Hello'},
 {name:'typed menu item then focus and type',text:'click Details menu item then focus Message field then type Hello',html:`<div role="menuitem" aria-expanded="false" onclick="events.push('details');this.setAttribute('aria-expanded','true');document.querySelector('#message').hidden=false">Details</div><button onclick="events.push('wrong')">Details</button><input id="message" hidden aria-label="Message">`,verified:3,events:['details'],value:'Hello'},
 {name:'prefix tab type then scoped fill',text:'click the tab named Account then fill Email in Account section with Hello',html:`<div role="tab" aria-selected="false" aria-controls="account" onclick="events.push('account');this.setAttribute('aria-selected','true');document.querySelector('#account').hidden=false">Account</div><div role="link" tabindex="0" onclick="events.push('wrong')">Account</div><section id="account" aria-label="Account" hidden><input id="message" aria-label="Email"></section>`,verified:2,events:['account'],value:'Hello'},
 {name:'wrong typed name stops before related target or text',text:'click Filters link then fill Message with Hello',html:`<label><input type="checkbox" onclick="events.push('wrong')">Filters</label><div role="link" tabindex="0" onclick="events.push('wrong')">Filters settings</div><input id="message" aria-label="Message">`,error:'step 1',events:[],value:''},
 {name:'mixed learned phrase uses fresh state',text:'Show Details then fill Message with Hello',html:details,verified:2,events:['details'],value:'Hello',modelCalls:2,acceptModel:true},
];
async function run(b,c){
 await b.evaluate(`document.body.innerHTML=${JSON.stringify(c.html)};globalThis.events=[];globalThis.submits=0;globalThis.textWrites=0;document.body.oninput=e=>{if(e.target.matches('input:not([type=checkbox]),textarea,[contenteditable]'))textWrites++};document.body.addEventListener('submit',e=>{e.preventDefault();submits++});`);await b.controller(controller);
 const child=spawn(binary,[],{stdio:['pipe','pipe','pipe']});let stderr='';child.stderr.on('data',d=>stderr+=d);
 const originalCall=b.call;
 const lines=createInterface({input:child.stdout});let observed=0,dispatched=0,modelCalls=0,done;const trace=[];
 const timer=setTimeout(()=>child.kill('SIGKILL'),15000);
 const exited=new Promise(resolve=>child.once('exit',(code,signal)=>resolve({code,signal})));
 child.stdin.write(c.text+'\n');
 try {
  for await(const line of lines){
   const request=JSON.parse(line);trace.push(request);let reply;
   if(request.kind==='done'){done=request;break;}
   if(request.kind==='observe'){
    observed++;
    if(c.replaceAt===observed)await b.controller(controller);
    if(c.hook?.[0]===observed)await b.evaluate(c.hook[1]);
    reply=await b.run('observe',{...(request.target?{target:request.target}:{})});
   }else if(request.kind==='dispatch'){
    dispatched++;
    if(c.delayTransport && dispatched===1){
      const original=b.call.bind(b);let delayed=false;
      b.call=async(method,params,page)=>{
        if(method==='Runtime.evaluate' && !delayed){delayed=true;await new Promise(resolve=>setTimeout(resolve,30));}
        return original(method,params,page);
      };
    }
    if(c.replaceBeforeDispatch===dispatched)await b.controller(controller);
    if(dispatched===2 && c.beforeSecondDispatch)await b.evaluate(c.beforeSecondDispatch);
    reply=await b.run(request.command.op,request.command);
   }else if(request.kind==='preflight'){
    modelCalls++;reply={accepted:!!c.acceptModel};
   }else if(request.kind==='propose'){
    modelCalls++;
    // Controlled model proposal exercises the mixed route, not model accuracy.
    const obs=request.observation,target=obs.candidates.find(x=>x.labels.includes('details'));
    reply={id:'fixture',operation:{operation:'activate',confidence:1},command:{op:'click',targetId:target?.id,documentId:obs.documentId,observationId:obs.observationId}};
   }else throw Error('Unknown fixture request '+request.kind);
   trace.push({reply});reply.clock=await b.evaluate('Date.now()');child.stdin.write(JSON.stringify(reply)+'\n');
  }
  child.stdin.end();const exit=await exited;
  assert.equal(exit.code,0,stderr || JSON.stringify(exit));assert(done,'missing result');
  if(c.error)assert(done.error?.includes(c.error),`${c.name}: ${JSON.stringify(done)}`);
  else {assert.equal(done.error,undefined,c.name);assert.equal(done.verified,c.verified,c.name);}
  const actual=await b.evaluate(`({events,submits,textWrites,value:document.querySelector('#message')?.value})`);
  assert.deepEqual(actual.events,c.events,c.name);assert.equal(actual.submits,0,c.name);
  assert.equal(actual.textWrites,c.writes ?? (c.verified && /\b(fill|type|copy|uppercase)\b/.test(c.text)?1:0),c.name);
  if('value' in c)assert.equal(actual.value,c.value,c.name);
  if(c.extra)assert.equal(await b.evaluate(c.extra),true,c.name);
  assert.equal(modelCalls,c.modelCalls || 0,c.name);
  return {name:c.name,passed:true,verified:done.verified ?? null,error:done.error ?? null,observed,dispatched,modelCalls,...actual};
 }catch(error){error.message+=`\nTrace: ${JSON.stringify(trace)}`;throw error;}finally {b.call=originalCall;clearTimeout(timer);child.stdin.end();if(child.exitCode===null)child.kill();}
}
(async()=>{const b=new Headless({virtualTime:true}),rows=[];try{
 await b.start();
 for(const c of cases.filter(c=>!process.env.VOICE_SEQUENCE_CASE || c.name===process.env.VOICE_SEQUENCE_CASE)){try{rows.push(await run(b,c));}catch(e){rows.push({name:c.name,passed:false,error:e.message});}}
 const sourceFiles=['voice/Sources/VoiceCore/BrowserSequence.swift','voice/Sources/VoiceCore/GroundedSequence.swift','voice/Sources/VoiceCore/Observation.swift','voice/Sources/LocalVoice/BrowserBridge.swift','voice/Sources/LocalVoice/LocalVoiceApp.swift','voice/browser/extension/controller.js','voice/browser/tests/headless.cjs','voice/tools/browser_sequence_check.swift','voice/browser/tests/sequences-headless.cjs'];
 const sourceSHA256=Object.fromEntries(sourceFiles.map(file=>[file,crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'../../..',file))).digest('hex')]));
 const report={sourceSHA256,browser:b.version.product,scope:'Actual Swift planner/executor; generated pages; simulated page clock; controlled model replies only in two routing cases; no microphone or personal browser',total:rows.length,passed:rows.filter(r=>r.passed).length,rows};
 console.log(JSON.stringify(report,null,2));if(report.passed!==report.total)process.exitCode=1;
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
