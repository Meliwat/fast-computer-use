// Actual Chrome DOM/default actions in an isolated world and disposable profile.
// Page networking is blocked; never attaches to the user's browser or microphone.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const assert=require('node:assert/strict');
const {Headless}=require('./headless.cjs');
const args=process.argv.slice(2);
const option=name=>{const index=args.indexOf(name);return index<0?null:args[index+1];};
const controller=option('--controller') || path.join(__dirname,'../extension/controller.js');
const source=fs.readFileSync(controller,'utf8');
const output=option('--output');
const cases=[
  {name:'native details opens',html:'<details><summary>Details</summary><input aria-label="Reference"></details>',target:'Details',outcome:'verified',read:'document.querySelector("details").open',value:true},
  {name:'native details closes',html:'<details open><summary>Details</summary><p>Contents</p></details>',target:'Details',outcome:'verified',read:'document.querySelector("details").open',value:false},
  {name:'pressed toggle',html:'<button aria-pressed="false">Grid view</button>',target:'Grid view',setup:'button.onclick=()=>button.setAttribute("aria-pressed","true")',outcome:'verified',read:'button.getAttribute("aria-pressed")',value:'true'},
  {name:'mixed toggle becomes on',read:'button.getAttribute("aria-pressed")',value:'true',html:'<button aria-pressed="mixed">Selection</button>',target:'Selection',setup:'button.onclick=()=>button.setAttribute("aria-pressed","true")',outcome:'verified'},
  {name:'native popover opens',html:'<button popovertarget="panel">Filters</button><div id="panel" popover>Filter options</div>',target:'Filters',outcome:'verified',read:'document.querySelector("#panel").matches(":popover-open")',value:true},
  {name:'native popover closes',html:'<button popovertarget="panel">Filters</button><div id="panel" popover>Filter options</div>',target:'Filters',setup:'document.querySelector("#panel").showPopover()',outcome:'verified',read:'document.querySelector("#panel").matches(":popover-open")',value:false},
  {name:'linked surface opens',html:'<button aria-controls="panel">Filters</button><section id="panel" hidden>Options</section>',target:'Filters',setup:'const panel=document.querySelector("#panel");button.onclick=()=>panel.hidden=false',outcome:'verified',read:'document.querySelector("#panel").hidden',value:false},
  {name:'linked surface opens after 220 ms',html:'<button aria-controls="panel">Filters</button><section id="panel" hidden>Options</section>',target:'Filters',setup:'const panel=document.querySelector("#panel");button.onclick=()=>setTimeout(()=>panel.hidden=false,220)',outcome:'verified',read:'document.querySelector("#panel").hidden',value:false},
  {name:'linked surface and state disagree',html:'<button aria-controls="panel" aria-expanded="false">Filters</button><section id="panel" hidden>Options</section>',target:'Filters',setup:'button.onclick=()=>button.setAttribute("aria-expanded","true")',outcome:'unverified'},
  {name:'linked dialog opens',html:'<button aria-controls="panel">Preferences</button><dialog id="panel"><input aria-label="Theme"></dialog>',target:'Preferences',setup:'const panel=document.querySelector("#panel");button.onclick=()=>panel.showModal()',outcome:'verified',read:'document.querySelector("#panel").open',value:true},
  {name:'brief delayed expansion reverts',html:'<button aria-expanded="false">Filters</button>',target:'Filters',setup:'button.onclick=()=>{setTimeout(()=>button.setAttribute("aria-expanded","true"),140);setTimeout(()=>button.setAttribute("aria-expanded","false"),220)}',outcome:'unverified'},
  {name:'malformed state is not proof',html:'<button aria-expanded="false">Filters</button>',target:'Filters',setup:'button.onclick=()=>button.setAttribute("aria-expanded","banana")',outcome:'unverified'},
  {name:'incidental mutation is not proof',html:'<button>Filters</button><p></p>',target:'Filters',setup:'const p=document.querySelector("p");button.onclick=()=>p.textContent="Unrelated content changed"',outcome:'unverified'},
  {name:'linked surface replacement is not proof',html:'<button aria-controls="panel">Filters</button><section id="panel" hidden>Options</section>',target:'Filters',setup:'const panel=document.querySelector("#panel");button.onclick=()=>{const next=panel.cloneNode(true);next.hidden=false;panel.replaceWith(next)}',outcome:'unverified'},
  {name:'changed association is not proof',html:'<button aria-controls="panel">Filters</button><section id="panel" hidden>Options</section><section id="other" hidden>Different options</section>',target:'Filters',setup:'const other=document.querySelector("#other");button.onclick=()=>{button.setAttribute("aria-controls","other");other.hidden=false}',outcome:'unverified'},
  {name:'detached control is not proof',html:'<button aria-expanded="false">Filters</button>',target:'Filters',setup:'button.onclick=()=>{button.setAttribute("aria-expanded","true");button.remove()}',outcome:'unverified'},
  {name:'ordinary stable expansion',read:'button.getAttribute("aria-expanded")',value:'true',html:'<button aria-expanded="false">Filters</button>',target:'Filters',setup:'button.onclick=()=>button.setAttribute("aria-expanded","true")',outcome:'verified'},
  {name:'ordinary selected tab',read:'button.getAttribute("aria-selected")',value:'true',html:'<button role="tab" aria-selected="false">Preview</button>',target:'Preview',setup:'button.onclick=()=>button.setAttribute("aria-selected","true")',outcome:'verified'},
  {name:'invalidates previous observation when target relation changes',html:'<button aria-controls="panel">Filters</button><section id="panel" hidden>Options</section><section id="other" hidden>Other options</section>',target:'Filters',setup:'button.onclick=()=>document.querySelector("#other").hidden=false',beforeDispatch:'button.setAttribute("aria-controls","other")',bound:true,outcome:'failed',clicks:0},
  {name:'linked surface is created lazily',read:'document.getElementById("panel")?.hidden',value:false,html:'<button aria-controls="panel">Filters</button>',target:'Filters',setup:'button.onclick=()=>{const panel=document.createElement("section");panel.id="panel";panel.textContent="Options";document.body.append(panel)}',outcome:'verified'},
  {name:'linked surface is removed on close',read:'document.getElementById("panel")===null',value:true,html:'<button aria-controls="panel">Filters</button><section id="panel">Options</section>',target:'Filters',setup:'const panel=document.querySelector("#panel");button.onclick=()=>panel.remove()',outcome:'verified'},
  {name:'duplicate surface IDs cannot verify',html:'<button aria-controls="panel" aria-expanded="false">Filters</button><section id="panel" hidden>Options</section><section id="panel" hidden>Other</section>',target:'Filters',setup:'button.onclick=()=>{button.setAttribute("aria-expanded","true");document.querySelector("#panel").hidden=false}',outcome:'unverified'},
  {name:'multiple surface references cannot verify',html:'<button aria-controls="one two" aria-expanded="false">Filters</button><section id="one" hidden>One</section><section id="two" hidden>Two</section>',target:'Filters',setup:'button.onclick=()=>button.setAttribute("aria-expanded","true")',outcome:'unverified'},
  {name:'popover opening can be cancelled by the page',html:'<button popovertarget="panel">Filters</button><div id="panel" popover>Options</div>',target:'Filters',setup:'document.querySelector("#panel").addEventListener("beforetoggle",event=>{if(event.newState==="open")event.preventDefault()})',outcome:'unverified',read:'document.querySelector("#panel").matches(":popover-open")',value:false},
  {name:'replacement invalidates a previously bound relation',html:'<button aria-controls="panel">Filters</button><section id="panel" hidden>Options</section>',target:'Filters',beforeDispatch:'const old=document.querySelector("#panel");old.replaceWith(old.cloneNode(true))',bound:true,outcome:'failed',clicks:0},
  {name:'open shadow root uses its own surface ID',html:'<div id="host"></div><section id="panel" hidden>Unrelated outside panel</section>',mount:'const host=document.querySelector("#host");host.attachShadow({mode:"open"}).innerHTML="<button aria-controls=panel>Filters</button><section id=panel hidden>Shadow options</section>"',pick:'document.querySelector("#host").shadowRoot.querySelector("button")',target:'Filters',setup:'const panel=button.getRootNode().getElementById("panel");button.onclick=()=>panel.hidden=false',outcome:'verified',read:'!button.getRootNode().getElementById("panel").hidden && document.querySelector("#panel").hidden',value:true},
  {name:'native popover in an open shadow root',read:'button.getRootNode().getElementById("panel").matches(":popover-open")',value:true,html:'<div id="host"></div>',mount:'document.querySelector("#host").attachShadow({mode:"open"}).innerHTML="<button popovertarget=panel>Filters</button><div id=panel popover>Shadow options</div>"',pick:'document.querySelector("#host").shadowRoot.querySelector("button")',target:'Filters',outcome:'verified'},
  {name:'only the first summary is a native disclosure',html:'<details open><summary>First</summary><summary>Second</summary></details>',pick:'document.querySelectorAll("summary")[1]',target:'Second',outcome:'failed',clicks:0},
  {name:'ARIA hidden alone does not visibly close a surface',html:'<button aria-controls="panel" aria-expanded="true">Filters</button><section id="panel">Still visible options</section>',target:'Filters',setup:'const panel=document.getElementById("panel");button.onclick=()=>{button.setAttribute("aria-expanded","false");panel.setAttribute("aria-hidden","true")}',outcome:'unverified',read:'document.getElementById("panel").getClientRects().length>0',value:true},
  {name:'inert alone does not visibly close a surface',html:'<button aria-controls="panel" aria-expanded="true">Filters</button><section id="panel">Still visible options</section>',target:'Filters',setup:'const panel=document.getElementById("panel");button.onclick=()=>{button.setAttribute("aria-expanded","false");panel.inert=true}',outcome:'unverified',read:'document.getElementById("panel").getClientRects().length>0',value:true},
  {name:'surface ID may contain punctuation and Unicode',read:'document.getElementById("9:filters?絵").hidden',value:false,html:'<button aria-controls="9:filters?絵">Filters</button><section id="9:filters?絵" hidden>Options</section>',target:'Filters',setup:'const panel=document.getElementById("9:filters?絵");button.onclick=()=>panel.hidden=false',outcome:'verified'},
];
(async()=>{
  const browser=new Headless(),rows=[];
  try {
    await browser.start();
    for(const c of cases){
      if(c.outcome==='verified')assert(c.read,'Positive cases need independent DOM outcome reads');
      await browser.evaluate(`document.body.innerHTML=${JSON.stringify(c.html)};${c.mount || ''};globalThis.clicks=0;globalThis.button=${c.pick || "document.querySelector('button,summary')"};(()=>{const button=globalThis.button;button.addEventListener('click',()=>clicks++);${c.setup || ''}})()`);
      await browser.controller(source);
      let request={target:c.target};
      if(c.bound){
        const observation=(await browser.run('observe',{target:c.target})).observation;
        assert.equal(observation.candidates.length,1,c.name);
        request={targetId:observation.candidates[0].id,documentId:observation.documentId,observationId:observation.observationId};
      }
      if(c.beforeDispatch)await browser.evaluate(c.beforeDispatch);
      const result=await browser.run('click',request);
      const clicks=await browser.evaluate('clicks');
      const value=c.read?await browser.evaluate(c.read):undefined;
      const passed=result.outcome===c.outcome && clicks===(c.clicks??1) && (!c.read || value===c.value);
      rows.push({name:c.name,passed,expectedOutcome:c.outcome,outcome:result.outcome,clicks,totalMs:result.totalMs??null,message:result.message??result.error,...(c.read?{value}:{}),...(result.transition?{transition:result.transition}:{})});
    }
    const report={scope:'Authored fixtures in isolated headless Chrome; actual default browser actions and isolated-world production controller. No user tabs, networking, speech, native host or app launch.',controllerSHA256:crypto.createHash('sha256').update(source).digest('hex'),testSHA256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),browser:browser.version.product,passed:rows.filter(r=>r.passed).length,total:rows.length,rows};
    if(output)fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
    console.log(JSON.stringify(report,null,2));
    if(report.passed!==report.total)process.exitCode=1;
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
