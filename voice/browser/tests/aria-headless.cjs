// Generic interactive ARIA widgets in disposable Chrome; no personal pages/input.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {Headless}=require('./headless.cjs');
const args=process.argv.slice(2),option=name=>{const i=args.indexOf(name);return i<0?null:args[i+1];};
const source=fs.readFileSync(option('--controller')||path.join(__dirname,'../extension/controller.js'),'utf8');
const output=option('--output');
const widget=(role,extra='')=>`<div id="target" role="${role}" tabindex="0" ${extra}>Night mode</div>`;
const on='control.onclick=()=>control.setAttribute("aria-checked","true")';
const checked='control.getAttribute("aria-checked")';
const cases=[
  {name:'custom menu item activates',html:widget('menuitem')+'<p id="effect"></p>',setup:'control.onclick=()=>document.querySelector("#effect").textContent="opened"',outcome:'unverified',read:'document.querySelector("#effect").textContent',value:'opened'},
  {name:'menu item opens a linked submenu',html:widget('menuitem','aria-expanded="false" aria-controls="panel"')+'<div id="panel" role="menu" hidden>Submenu</div>',setup:'control.onclick=()=>{control.setAttribute("aria-expanded","true");document.querySelector("#panel").hidden=false}',outcome:'verified',read:'document.querySelector("#panel").hidden',value:false},
  {name:'custom switch toggles',html:widget('switch','aria-checked="false"'),setup:on,outcome:'verified',read:checked,value:'true'},
  {name:'button switch uses aria checked',html:'<button id="target" role="switch" aria-checked="false">Night mode</button>',setup:on,outcome:'verified',read:checked,value:'true'},
  {name:'native checkbox activates through click',html:'<label>Night mode<input id="target" type="checkbox"></label>',outcome:'verified',read:'control.checked',value:true},
  {name:'native checkbox switch uses native checked',html:'<label>Night mode<input id="target" type="checkbox" role="switch"></label>',outcome:'verified',read:'control.checked',value:true},
  {name:'native radio activates through click',html:'<label>Night mode<input id="target" type="radio" name="theme"></label><input id="other" type="radio" name="theme" checked>',outcome:'verified',read:'control.checked && !document.querySelector("#other").checked',value:true},
  {name:'custom radio changes group selection',html:'<div role="radiogroup">'+widget('radio','aria-checked="false"')+'<div id="other" role="radio" aria-checked="true">Day mode</div></div>',setup:'control.onclick=()=>{control.setAttribute("aria-checked","true");document.querySelector("#other").setAttribute("aria-checked","false")}',outcome:'verified',read:'control.getAttribute("aria-checked")==="true" && document.querySelector("#other").getAttribute("aria-checked")==="false"',value:true},
  {name:'menu checkbox activates',html:'<div role="menu">'+widget('menuitemcheckbox','aria-checked="false"')+'</div>',setup:on,outcome:'verified',read:checked,value:'true'},
  {name:'menu radio activates',html:'<div role="menu">'+widget('menuitemradio','aria-checked="false"')+'</div>',setup:on,outcome:'verified',read:checked,value:'true'},
  {name:'custom checkbox visible text supplies label',html:widget('checkbox','aria-checked="false"'),setup:on,outcome:'verified',read:checked,value:'true'},
  {name:'listbox option selected state changes',html:'<div role="listbox">'+widget('option','aria-selected="false"')+'</div>',setup:'control.onclick=()=>control.setAttribute("aria-selected","true")',outcome:'verified',read:'control.getAttribute("aria-selected")',value:'true'},
  {name:'listbox option checked state changes',html:'<div role="listbox" aria-multiselectable="true">'+widget('option','aria-checked="false"')+'</div>',setup:on,outcome:'verified',read:checked,value:'true'},
  {name:'custom link uses visible text',html:widget('link')+'<p id="effect"></p>',setup:'control.onclick=()=>document.querySelector("#effect").textContent="opened"',outcome:'unverified',read:'document.querySelector("#effect").textContent',value:'opened'},
  {name:'mixed checkbox can become checked',html:widget('checkbox','aria-checked="mixed"'),setup:on,outcome:'verified',read:checked,value:'true'},
  {name:'mixed switch is not valid verification evidence',html:widget('switch','aria-checked="mixed"'),setup:on,outcome:'unverified',read:checked,value:'true'},
  {name:'malformed resulting state is unverified',html:widget('checkbox','aria-checked="false"'),setup:'control.onclick=()=>control.setAttribute("aria-checked","banana")',outcome:'unverified',read:checked,value:'banana'},
  {name:'reverted switch is not reported verified',html:widget('switch','aria-checked="false"'),setup:'control.onclick=()=>{control.setAttribute("aria-checked","true");setTimeout(()=>control.setAttribute("aria-checked","false"),60)}',outcome:'unverified',read:checked,value:'false'},
  {name:'unchanged switch is acknowledged without success claim',html:widget('switch','aria-checked="false"'),outcome:'unverified',read:checked,value:'false'},
  {name:'explicit check sets a switch once',html:widget('switch','aria-checked="false"'),setup:on,op:'check',request:{checked:true},outcome:'verified',read:checked,value:'true'},
  {name:'explicit check preserves an already checked switch',html:widget('switch','aria-checked="true"'),setup:'control.onclick=()=>control.setAttribute("aria-checked","false")',op:'check',request:{checked:true},clicks:0,outcome:'verified',read:checked,value:'true'},
  {name:'explicit uncheck works for menu checkbox',html:widget('menuitemcheckbox','aria-checked="true"'),setup:'control.onclick=()=>control.setAttribute("aria-checked","false")',op:'check',request:{checked:false},outcome:'verified',read:checked,value:'false'},
  {name:'check rejects malformed initial state without input',html:widget('checkbox','aria-checked="banana"'),setup:on,op:'check',request:{checked:true},outcome:'failed',clicks:0,read:checked,value:'banana'},
  {name:'check rejects missing requested boolean before input',html:'<label>Night mode<input id="target" type="checkbox"></label>',op:'check',outcome:'failed',clicks:0,read:'control.checked',value:false},
  {name:'check detects delayed native indeterminate state',html:'<label>Night mode<input id="target" type="checkbox"></label>',setup:'control.onclick=()=>setTimeout(()=>control.indeterminate=true,60)',op:'check',request:{checked:true},outcome:'failed',read:'control.indeterminate',value:true},
  {name:'disabled fieldset prevents native activation',html:'<fieldset disabled><label>Night mode<input id="target" type="checkbox"></label></fieldset>',outcome:'failed',clicks:0,enabled:false,read:'control.checked',value:false},
  {name:'disabled menu item is not activated',html:widget('menuitem','aria-disabled="true"'),outcome:'failed',clicks:0,enabled:false},
  {name:'disabled ancestor prevents custom activation',html:'<div aria-disabled="true">'+widget('switch','aria-checked="false"')+'</div>',setup:on,outcome:'failed',clicks:0,enabled:false,read:checked,value:'false'},
  {name:'duplicate options are not guessed',html:widget('option','aria-selected="false"')+'<div role="option" aria-selected="false">Night mode</div>',outcome:'failed',clicks:0},
  {name:'bound role change invalidates old observation',html:widget('switch','aria-checked="false"'),setup:on,bound:true,beforeDispatch:'control.setAttribute("role","checkbox")',outcome:'failed',clicks:0},
  {name:'native input type change invalidates binding',html:'<label>Night mode<input id="target" type="checkbox"></label>',bound:true,beforeDispatch:'control.type="radio"',outcome:'failed',clicks:0},
  {name:'native type change invalidates binding even with explicit role',html:'<label>Night mode<input id="target" type="checkbox" role="checkbox"></label>',bound:true,beforeDispatch:'control.type="radio"',outcome:'failed',clicks:0},
  {name:'open shadow root switch activates',html:'<div id="host"></div>',mount:`document.querySelector('#host').attachShadow({mode:'open'}).innerHTML=${JSON.stringify(widget('switch','aria-checked="false"'))}`,pick:'document.querySelector("#host").shadowRoot.querySelector("#target")',setup:on,outcome:'verified',read:checked,value:'true'},
  {name:'disabled shadow host prevents activation',html:'<div id="host" aria-disabled="true"></div>',mount:`document.querySelector('#host').attachShadow({mode:'open'}).innerHTML=${JSON.stringify(widget('switch','aria-checked="false"'))}`,pick:'document.querySelector("#host").shadowRoot.querySelector("#target")',setup:on,outcome:'failed',clicks:0,enabled:false,read:checked,value:'false'},
  {name:'aria-hidden shadow host excludes its control',html:'<div id="host" aria-hidden="true"></div>',mount:`document.querySelector('#host').attachShadow({mode:'open'}).innerHTML=${JSON.stringify(widget('switch','aria-checked="false"'))}`,pick:'document.querySelector("#host").shadowRoot.querySelector("#target")',setup:on,outcome:'failed',clicks:0,observed:false,read:checked,value:'false'},
  {name:'inert shadow host excludes its control',html:'<div id="host" inert></div>',mount:`document.querySelector('#host').attachShadow({mode:'open'}).innerHTML=${JSON.stringify(widget('switch','aria-checked="false"'))}`,pick:'document.querySelector("#host").shadowRoot.querySelector("#target")',setup:on,outcome:'failed',clicks:0,observed:false,read:checked,value:'false'},
  {name:'plain named text is not made clickable',html:'<p id="target">Night mode</p>',outcome:'failed',clicks:0,observed:false},
];
(async()=>{const browser=new Headless({virtualTime:true}),rows=[];let stage='browser startup';try{
  await browser.start();
  // These fixtures assert nominal timer ordering, not wall-clock latency. VM stalls
  // may otherwise defer a main-world 60 ms reversal beyond the 120 ms verifier.
  const pausedAt=await browser.evaluate('Date.now()');
  await new Promise(resolve=>setTimeout(resolve,30));
  assert.equal(await browser.evaluate('Date.now()'),pausedAt,'Fixture clock must stay paused between actions');
  for(const c of cases){
    console.error(`[ARIA ${rows.length+1}/${cases.length}] ${c.name}`);
    stage=`${c.name}: fixture setup`;
    await browser.evaluate(`document.body.innerHTML=${JSON.stringify(c.html)};${c.mount||''};globalThis.clicks=0;globalThis.control=${c.pick||'document.querySelector("#target")'};control.addEventListener('click',()=>clicks++);${c.setup||''}`);
    stage=`${c.name}: controller installation`;
    await browser.controller(source);
    stage=`${c.name}: observation`;
    const observation=(await browser.run('observe')).observation;
    const candidates=observation.candidates.filter(x=>x.labels.includes('night mode'));
    const observed=candidates.some(x=>x.clickable);
    let request={target:'Night mode',...(c.request||{})};
    if(c.bound && candidates.length===1){request={...request,targetId:candidates[0].id,documentId:observation.documentId,observationId:observation.observationId};}
    if(c.beforeDispatch)await browser.evaluate(c.beforeDispatch);
    stage=`${c.name}: ${c.op||'click'} dispatch and verification`;
    const result=await browser.run(c.op||'click',request);
    stage=`${c.name}: independent effect read`;
    const clicks=await browser.evaluate('clicks');const value=c.read?await browser.evaluate(c.read):undefined;
    const passed=result.outcome===c.outcome && clicks===(c.clicks??1) && observed===(c.observed??true) &&
      (c.enabled===undefined || candidates.every(x=>x.enabled===c.enabled)) && (!c.read || value===c.value);
    rows.push({name:c.name,passed,observed,outcome:result.outcome,expectedOutcome:c.outcome,clicks,
      message:result.message||result.error,totalMs:result.totalMs??null,...(c.read?{value}:{}),...(result.transition?{transition:result.transition}:{})});
  }
  const report={scope:'Authored standard-widget fixtures, production controller in isolated headless Chrome. Independent DOM effects and click counters. Simulated page clock tests timer ordering, not latency. No personal browser, speech, native host or app launch.',controllerSHA256:crypto.createHash('sha256').update(source).digest('hex'),testSHA256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),browser:browser.version.product,passed:rows.filter(r=>r.passed).length,total:rows.length,rows};
  if(output)fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify(report,null,2));if(report.passed!==report.total)process.exitCode=1;
}catch(error){throw new Error(`ARIA fixture failed during ${stage}`,{cause:error});}
finally{await browser.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
