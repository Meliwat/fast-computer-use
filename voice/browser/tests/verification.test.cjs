// DOM simulation only; no Chrome, user tabs or desktop input.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../extension/controller.js'),'utf8');
function fixture(html) {
  const dom=new JSDOM(html,{url:'https://fixture.test/',runScripts:'outside-only',pretendToBeVisual:true});
  const w=dom.window;
  w.document.hasFocus=()=>true;
  w.HTMLElement.prototype.getClientRects=function(){return this.hidden?[]:[this.getBoundingClientRect()];};
  w.HTMLElement.prototype.getBoundingClientRect=function(){return {x:10,y:10,left:10,top:10,right:130,bottom:40,width:120,height:30};};
  w.HTMLElement.prototype.scrollBy=function({top}){this.scrollTop=Math.max(0,Math.min(this.scrollHeight-this.clientHeight,this.scrollTop+top));};
  require('./editing-stub.cjs')(w);
  w.eval(source);
  const run=(op,rest={})=>w.LocalVoiceDOM.runVerified({op,expectedURL:w.location.href,deadline:Date.now()+1800,...rest});
  return {w,run,close:()=>w.close()};
}
test('observations expose bounded target identities, not field contents',async()=>{
  const f=fixture('<input aria-label="Search" value="private draft"><button>Go</button>');
  try {
    const {observation}=await f.run('observe');
    assert.equal(observation.candidates.length,2);
    assert.equal(JSON.stringify(observation).includes('private draft'),false);
    const input=observation.candidates[0];
    const result=await f.run('fill',{targetId:input.id,documentId:observation.documentId,observationId:observation.observationId,value:'hello'});
    assert.equal(result.outcome,'verified');
    assert.equal(JSON.stringify(result.evidence).includes('hello'),false);
  } finally {f.close();}
});
test('delayed framework reversion is a failed effect, not success',async()=>{
  const f=fixture('<input aria-label="Search">');
  try {
    f.w.document.querySelector('input').oninput=e=>f.w.setTimeout(()=>e.target.value='',50);
    const result=await f.run('fill',{target:'Search',value:'test'});
    assert.equal(result.outcome,'failed');assert.match(result.error,/reverted/);
  } finally {f.close();}
});
test('incidental mutation does not verify a click',async()=>{
  const f=fixture('<button>Explore</button><p></p>');
  try {
    f.w.document.querySelector('button').onclick=()=>f.w.document.querySelector('p').textContent='unrelated ad updated';
    assert.equal((await f.run('click',{target:'Explore'})).outcome,'unverified');
  } finally {f.close();}
});
test('expanded control transition is verified',async()=>{
  const f=fixture('<button aria-expanded="false">Options</button>');
  try {
    const button=f.w.document.querySelector('button');button.onclick=()=>button.setAttribute('aria-expanded','true');
    assert.equal((await f.run('click',{target:'Options'})).outcome,'verified');
  } finally {f.close();}
});
test('detached target is rejected before input',async()=>{
  const f=fixture('<input aria-label="Search">');
  try {
    const {observation}=await f.run('observe');f.w.document.querySelector('input').remove();
    const result=await f.run('fill',{targetId:observation.candidates[0].id,documentId:observation.documentId,observationId:observation.observationId,value:'test'});
    assert.equal(result.ok,false);assert.match(result.error,/no longer/);
  } finally {f.close();}
});
test('duplicate labels abstain; exact target ID resolves ambiguity',async()=>{
  const f=fixture('<input aria-label="Search"><input aria-label="Search">');
  try {
    assert.equal((await f.run('fill',{target:'Search',value:'test'})).ok,false);
    const {observation}=await f.run('observe');
    const result=await f.run('fill',{targetId:observation.candidates[1].id,documentId:observation.documentId,observationId:observation.observationId,value:'test'});
    assert.equal(result.outcome,'verified');assert.equal(f.w.document.querySelectorAll('input')[0].value,'');
  } finally {f.close();}
});
test('scroll verifies offset and distinguishes a boundary',async()=>{
  const f=fixture('<main style="overflow-y:auto"><input></main>');
  try {
    const el=f.w.document.querySelector('main');
    Object.defineProperties(el,{scrollHeight:{value:600},clientHeight:{value:300}});
    f.w.document.querySelector('input').focus();
    assert.equal((await f.run('scroll',{value:'down'})).outcome,'verified');
    el.scrollTop=300;
    const result=await f.run('scroll',{value:'down'});
    assert.equal(result.outcome,'unverified');assert.match(result.message,/boundary/);
  } finally {f.close();}
});
test('focused insertion is verified and never submits',async()=>{
  const f=fixture('<form><input value="Hello friend"><button>Send</button></form>');
  try {
    let count=0;f.w.document.querySelector('form').onsubmit=e=>{e.preventDefault();count++;};
    const el=f.w.document.querySelector('input');el.focus();el.setSelectionRange(6,12);
    const result=await f.run('type',{value:'world'});
    assert.equal(result.outcome,'verified');assert.equal(el.value,'Hello world');assert.equal(count,0);
  } finally {f.close();}
});
test('focus change during verification fails without replay',async()=>{
  const f=fixture('<button aria-expanded="false">Options</button>');
  try {
    let count=0;f.w.document.querySelector('button').onclick=()=>{count++;f.w.document.hasFocus=()=>false;};
    const result=await f.run('click',{target:'Options'});
    assert.equal(result.ok,false);assert.match(result.error,/focus/);assert.equal(count,1);
  } finally {f.close();}
});
test('verification does not hide expired or wrong-document requests',async()=>{
  const f=fixture('<input aria-label="Search">');
  try {
    assert.equal((await f.run('fill',{target:'Search',value:'hi',deadline:0})).ok,false);
    const {observation}=await f.run('observe');
    assert.equal((await f.run('fill',{targetId:observation.candidates[0].id,documentId:'old',value:'hi'})).ok,false);
    assert.equal(f.w.document.querySelector('input').value,'');
  } finally {f.close();}
});

test('relabelled target ID is not acted on from a stale observation',async()=>{
  const f=fixture('<input aria-label="Search">');
  try {
    const {observation}=await f.run('observe');
    f.w.document.querySelector('input').setAttribute('aria-label','Payment');
    const result=await f.run('fill',{targetId:observation.candidates[0].id,documentId:observation.documentId,observationId:observation.observationId,value:'test'});
    assert.equal(result.ok,false);assert.match(result.error,/changed since/);
    assert.equal(f.w.document.querySelector('input').value,'');
  } finally {f.close();}
});
test('same-document navigation is verified against the selected link',async()=>{
  const f=fixture('<a href="/explore">Explore</a>');
  try {
    f.w.document.querySelector('a').onclick=e=>{e.preventDefault();f.w.history.pushState({},'', '/explore');};
    assert.equal((await f.run('click',{target:'Explore'})).outcome,'verified');
  } finally {f.close();}
});

test('target-scoped click observation scans past the first 48 unrelated controls without clicking',async()=>{
  const f=fixture('<button>Settings</button>'.repeat(60)+'<button>Explore</button>');
  try {
    let clicks=0;for(const button of f.w.document.querySelectorAll('button'))button.onclick=()=>clicks++;
    const {observation}=await f.run('observe',{target:'Explore'});
    assert.equal(observation.truncated,false);assert.equal(observation.candidates.length,1);
    assert.deepEqual([...observation.candidates[0].labels],['explore']);assert.equal(clicks,0);
    const missing=await f.run('observe',{target:'Missing'});
    assert.equal(missing.observation.candidates.length,0);assert.equal(clicks,0);
  }finally{f.close();}
});
test('removing state attributes or detaching a control does not verify a click',async()=>{
  for(const change of [el=>el.removeAttribute('aria-expanded'),el=>el.remove()]) {
    const f=fixture('<button aria-expanded="false">Options</button>');
    try {
      const button=f.w.document.querySelector('button');button.onclick=()=>change(button);
      assert.equal((await f.run('click',{target:'Options'})).outcome,'unverified');
    }finally{f.close();}
  }
});

test('click Search focuses a search field, then typing inserts without submitting',async()=>{
  const f=fixture('<input role="combobox" aria-label="Search query" placeholder="Search"><button>Post</button>');
  try {
    let posts=0;f.w.document.querySelector('button').onclick=()=>posts++;
    const result=await f.run('click',{target:'Search'});
    assert.equal(result.ok,true,result.error);
    assert.equal(result.outcome,'verified');
    assert.equal(f.w.document.activeElement,f.w.document.querySelector('input'));
    assert.equal((await f.run('type',{value:'local AI'})).ok,true);
    assert.equal(f.w.document.querySelector('input').value,'local AI');assert.equal(posts,0);
  }finally{f.close();}
});
test('a zero-height document scroller scrolls by the viewport instead of one pixel',async()=>{
  const f=fixture('<main>Feed</main>');
  try {
    const root=f.w.document.documentElement;
    Object.defineProperties(root,{scrollHeight:{value:4000},clientHeight:{value:0}});
    const result=await f.run('scroll',{value:'down'});
    assert.equal(result.outcome,'verified');
    assert.ok(root.scrollTop>=f.w.innerHeight*.75,`Only moved ${root.scrollTop}px`);
  }finally{f.close();}
});
test('capability negotiation distinguishes verified dispatch from an old direct dispatcher',async()=>{
  const f=fixture('<input aria-label="Search">');
  try {
    const verified=await f.run('capabilities');
    assert.equal(verified.ok,true);assert.equal(verified.protocolVersion,2);assert.equal(verified.verifiedDispatch,true);
    const legacy=f.w.LocalVoiceDOM.run({op:'capabilities',expectedURL:f.w.location.href,deadline:Date.now()+1800});
    assert.equal(legacy.ok,true);assert.equal(legacy.verifiedDispatch,false);
    assert.equal(f.w.document.querySelector('input').value,'');
  } finally {f.close();}
});

test('native summary labels support default disclosure activation',async()=>{
  const f=fixture('<details><summary>Details</summary><p>Content</p></details>');
  try {
    const result=await f.run('click',{target:'Details'});
    assert.equal(result.outcome,'verified');
    assert.equal(f.w.document.querySelector('details').open,true);
    assert.equal(result.transition.surface,'details');
  }finally{f.close();}
});
test('pressed buttons verify a stable toggle, not an invalid ARIA value',async()=>{
  for(const value of ['true','banana']) {
    const f=fixture('<button aria-pressed="false">Grid</button>');
    try {
      let clicks=0;const button=f.w.document.querySelector('button');
      button.onclick=()=>{clicks++;button.setAttribute('aria-pressed',value);};
      const result=await f.run('click',{target:'Grid'});
      assert.equal(result.outcome,value==='true'?'verified':'unverified');assert.equal(clicks,1);
    }finally{f.close();}
  }
});
test('changed controlled-surface identity invalidates a bound click before dispatch',async()=>{
  const f=fixture('<button aria-controls="panel">Filters</button><section id="panel" hidden></section>');
  try {
    const observation=(await f.run('observe',{target:'Filters'})).observation;
    const panel=f.w.document.querySelector('#panel');panel.replaceWith(panel.cloneNode(true));
    let clicks=0;f.w.document.querySelector('button').onclick=()=>clicks++;
    const result=await f.run('click',{targetId:observation.candidates[0].id,documentId:observation.documentId,observationId:observation.observationId});
    assert.equal(result.ok,false);assert.match(result.error,/changed since/);assert.equal(clicks,0);
  }finally{f.close();}
});
