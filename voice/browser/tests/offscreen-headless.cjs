// Authored generic layouts in disposable Chrome. No personal tabs, network or screen capture.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {Headless}=require('./headless.cjs');
const args=process.argv.slice(2),option=name=>{const i=args.indexOf(name);return i<0?null:args[i+1]};
const sourcePath=option('--controller') || path.join(__dirname,'../extension/controller.js');
const source=fs.readFileSync(sourcePath,'utf8'),output=option('--output');
const at=(html,position='top:2000px;left:40px')=>`<div style="position:absolute;${position}">${html}</div>`;
const button='<button id="target" aria-pressed="false" onclick="actions.push(this.id);this.setAttribute(\'aria-pressed\',\'true\')">Details</button>';
const input='<input id="target" aria-label="Message">';
const cases=[
 {name:'bound button below viewport',html:at(button),target:'Details',act:true},
 {name:'named button below viewport',html:at(button),target:'Details',bound:false,act:true},
 {name:'bound field below viewport focuses',html:at(input),target:'Message field',focus:true},
 {name:'named field below viewport fills',html:at(input),target:'Message',op:'fill',value:'Hello',bound:false,text:'Hello'},
 {name:'bound field below viewport fills',html:at(input),target:'Message',op:'fill',value:'Hello',text:'Hello'},
 {name:'native checkbox below viewport',html:at('<label><input id="target" type="checkbox" onclick="actions.push(this.id)">Alerts</label>'),target:'Alerts checkbox',op:'check',checked:true,act:true,writes:1,read:'target.checked',expected:true},
 {name:'select below viewport',html:at('<label>Color<select id="target"><option>Blue</option><option>Red</option></select></label>'),target:'Color',op:'select',value:'Red',writes:1,read:'target.value',expected:'Red'},
 {name:'horizontal scroll to named control',html:at(button,'top:120px;left:2400px'),target:'Details',act:true},
 {name:'scroll upwards to named control',html:at(button,'top:30px;left:40px'),setup:'scrollTo(0,2500)',target:'Details',act:true},
 {name:'scroll a nested container',html:`<div id="pane" style="height:160px;width:500px;overflow:auto;position:relative"><div style="height:900px">${at(button,'top:650px;left:40px')}</div></div>`,target:'Details',act:true,nested:true},
 {name:'nested container below page viewport',html:at(`<div id="pane" style="height:180px;width:500px;overflow:auto;position:relative"><div style="height:900px">${at(button,'top:650px;left:40px')}</div></div>`),target:'Details',act:true,nested:true},
 {name:'open shadow root scrolls',html:'<div id="host"></div>',setup:`host.attachShadow({mode:'open'}).innerHTML=${JSON.stringify(at(button))}`,pick:'host.shadowRoot.querySelector("#target")',target:'Details',act:true},
 {name:'smooth page setting does not defer action',html:at(button),setup:'document.documentElement.style.scrollBehavior="smooth"',target:'Details',act:true},
 {name:'target in a named form',html:`<form aria-label="Billing" style="height:3500px">${at(input)}</form>`,target:'Message in Billing form',op:'fill',value:'Hello',text:'Hello'},
 {name:'scoped field remains verified after its edit moves it',html:`<form aria-label="Billing" style="height:3500px">${at(input.replace('aria-label="Message"','aria-label="Message" oninput="scrollBy(0,2)"'))}</form>`,target:'Message in Billing form',op:'fill',value:'Hello',text:'Hello'},
 {name:'scoped relabel after edit is not verified',html:`<form aria-label="Billing" style="height:3500px">${at(input.replace('aria-label="Message"','aria-label="Message" oninput="this.setAttribute(\'aria-label\',\'Different\')"'))}</form>`,target:'Message in Billing form',op:'fill',value:'Hello',text:'Hello',reject:true},
 {name:'entire named form starts below viewport',html:at(`<form aria-label="Billing">${input}</form>`),target:'Message in Billing form',op:'fill',value:'Hello',text:'Hello'},
 {name:'named heading can scroll out of view',html:`<section style="height:3500px"><h2>Billing</h2>${at(input)}</section>`,target:'Message in Billing section',op:'fill',value:'Hello',text:'Hello'},
 {name:'binding without document refuses before scroll',html:at(button),target:'Details',omitDocument:true,reject:true,noScroll:true},
 {name:'frame timeout sends no click',html:at(button),target:'Details',isolatedBefore:'globalThis.requestAnimationFrame=()=>0',reject:true,error:'did not render'},
 {name:'wrong visible type cannot choose a related offscreen label',html:'<input type="checkbox" aria-label="Details">'+at(button.replace('Details','Details settings').replace('<button','<button role="link"')),target:'Details link',reject:true,noScroll:true},
 {name:'fixed offscreen target is not scroll reachable',html:button.replace('<button','<button style="position:fixed;top:2000px"'),target:'Details',reject:true,noScroll:true},
 {name:'readonly offscreen field is not scrolled for a fill',html:at(input.replace('<input','<input readonly')),target:'Message',op:'fill',value:'Hello',bound:false,reject:true,noScroll:true},
 {name:'visible match retains priority',html:button+at(button.replace('id="target"','id="other"')),target:'Details',act:true,noScroll:true},
 {name:'two offscreen homonyms refuse',html:at(button)+at(button.replace('id="target"','id="other"'),'top:2300px;left:40px'),target:'Details',reject:true,noScroll:true},
 {name:'unbound homonyms refuse',html:at(button)+at(button.replace('id="target"','id="other"'),'top:2300px;left:40px'),target:'Details',bound:false,reject:true,noScroll:true},
 {name:'untargeted observation stays within viewport',html:at(button),target:'Details',inventoryOnly:true,noScroll:true},
 {name:'named observation retains offscreen link destination',html:at('<a id="target" href="https://example.invalid/destination">Details</a>'),target:'Details',observeOnly:true,navigationURL:'https://example.invalid/destination',noScroll:true},
 {name:'hidden content visibility does not invite reveal',html:`<div style="content-visibility:hidden">${at(button)}</div>`,target:'Details',reject:true,noScroll:true},
 {name:'hidden overflow does not invite reveal',html:`<div style="height:120px;width:500px;overflow:hidden;position:relative">${at(button,'top:650px;left:40px')}</div>`,target:'Details',reject:true,noScroll:true},
 {name:'disabled offscreen target refuses',html:at(button.replace('<button','<button disabled')),target:'Details',reject:true,noScroll:true},
 {name:'hidden attribute does not invite reveal',html:at(button.replace('<button','<button hidden')),target:'Details',reject:true,noScroll:true},
 {name:'display none does not invite reveal',html:`<div style="display:none">${at(button)}</div>`,target:'Details',reject:true,noScroll:true},
 {name:'opacity zero does not invite reveal',html:`<div style="opacity:0">${at(button)}</div>`,target:'Details',reject:true,noScroll:true},
 {name:'aria hidden does not invite reveal',html:`<div aria-hidden="true">${at(button)}</div>`,target:'Details',reject:true,noScroll:true},
 {name:'inert does not invite reveal',html:`<div inert>${at(button)}</div>`,target:'Details',reject:true,noScroll:true},
 {name:'closed disclosure is not a scroll problem',html:`<details><summary>Settings</summary>${at(button)}</details>`,target:'Details',reject:true,noScroll:true},
 {name:'password field remains excluded',html:at(input.replace('<input','<input type="password"')),target:'Message',op:'fill',value:'Hello',bound:false,reject:true,noScroll:true},
 {name:'non scrolling clip does not invite reveal',html:`<div style="height:120px;width:500px;overflow:clip;position:relative">${at(button,'top:650px;left:40px')}</div>`,target:'Details',reject:true,noScroll:true},
 {name:'fixed overlay blocks actual click after reveal',html:at(button)+'<div style="position:fixed;inset:0;z-index:100;background:white">Overlay</div>',target:'Details',reject:true},
 {name:'replacement during scroll stops input',html:at(button),target:'Details',hook:'target.outerHTML=target.outerHTML',reject:true},
 {name:'label change during scroll stops input',html:at(button),target:'Details',hook:'target.textContent="Different"',reject:true},
 {name:'type change during scroll stops input',html:at(input),target:'Message',op:'fill',value:'Hello',hook:'target.type="password"',reject:true},
 {name:'new duplicate during scroll stops input',html:at(button),target:'Details',hook:`document.body.insertAdjacentHTML('beforeend',${JSON.stringify('<button style="position:fixed;top:20px">Details</button>')})`,reject:true},
 {name:'URL change during scroll stops input',html:at(button),target:'Details',hook:'location.hash="#changed"',reject:true},
 {name:'modal appearing during scroll stops input',html:at(button),target:'Details',hook:`document.body.insertAdjacentHTML('beforeend',${JSON.stringify('<dialog open aria-modal="true" style="position:fixed;top:10px">Notice</dialog>')})`,reject:true},
 {name:'bound target relabelled before scroll refuses',html:at(button),target:'Details',before:'target.textContent="Different"',reject:true,noScroll:true},
 {name:'invalid check boolean causes no movement',html:at('<label><input id="target" type="checkbox">Alerts</label>'),target:'Alerts',op:'check',bound:false,reject:true,noScroll:true},
 {name:'text reversion is detected without repeated edits',html:at(input.replace('aria-label="Message"','aria-label="Message" oninput="setTimeout(()=>this.value=\'\',60)"')),target:'Message',op:'fill',value:'Hello',text:'',reject:true,writes:1},
];
(async()=>{const browser=new Headless(),rows=[];try{
 await browser.start();
 await browser.evaluate('globalThis.__fixtureRAF=requestAnimationFrame',true);
 for(const c of cases.filter(c=>!process.env.VOICE_OFFSCREEN_CASE || c.name===process.env.VOICE_OFFSCREEN_CASE)){
  let result,observation,actual;
  try{
   await browser.evaluate('globalThis.requestAnimationFrame=globalThis.__fixtureRAF',true);
   await browser.evaluate(`window.onscroll=null;document.documentElement.style.scrollBehavior='auto';document.body.style='min-height:4200px;min-width:3200px';document.body.innerHTML=${JSON.stringify(c.html)};globalThis.actions=[];globalThis.writes=0;globalThis.hookRuns=0;document.body.oninput=()=>writes++;scrollTo({top:0,left:0,behavior:'instant'});${c.setup||''};globalThis.target=${c.pick||'document.querySelector("#target")'};`);
   await browser.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
   await browser.controller(source);
   // Setup scroll events have completed before observing or installing mutation hooks.
   observation=(await browser.run('observe',c.inventoryOnly?{}:{target:c.target})).observation;
   const before=await browser.evaluate('({x:scrollX,y:scrollY,pane:document.querySelector("#pane")?.scrollTop||0})');
   if(c.hook)await browser.evaluate(`window.onscroll=()=>{window.onscroll=null;hookRuns++;${c.hook}}`);
   if(c.before)await browser.evaluate(c.before);
   if(c.isolatedBefore)await browser.evaluate(c.isolatedBefore,true);
   let command={target:c.target,...('value' in c?{value:c.value}:{}),...('checked' in c?{checked:c.checked}:{})};
   const eligible=observation.candidates.filter(x=>x.enabled && (c.op==='select'?x.role==='select':c.op==='fill'?x.editable:x.clickable));
   if(c.observeOnly || c.inventoryOnly){
    assert.equal(eligible.length,c.observeOnly?1:0,c.name);
    if(c.observeOnly){assert.equal(eligible[0].offscreen,true,c.name);assert.equal(eligible[0].navigationURL,c.navigationURL,c.name);}
   }else if(c.bound===false)result=await browser.run(c.op||'click',command);
   else if(eligible.length===1)result=await browser.run(c.op||'click',{...command,targetId:eligible[0].id,documentId:c.omitDocument?undefined:observation.documentId,observationId:observation.observationId});
   actual=await browser.evaluate(`({actions,writes,hookRuns,value:target?.value,focused:(document.activeElement?.shadowRoot?.activeElement||document.activeElement)===target,x:scrollX,y:scrollY,pane:document.querySelector('#pane')?.scrollTop||0,...${c.read?`{read:${c.read}}`:'{}'}})`);
   assert.deepEqual(actual.actions,c.act?['target']:[],c.name);
   assert.equal(actual.writes,c.writes ?? ('text' in c?1:0),c.name);
   if(c.reject)assert.notEqual(result?.outcome,'verified',c.name);
   else if(!c.observeOnly && !c.inventoryOnly)assert.equal(result?.outcome,'verified',c.name);
   if(c.error)assert(result?.error?.includes(c.error),c.name);
   if(c.focus)assert.equal(actual.focused,true,c.name);
   if('text' in c)assert.equal(actual.value,c.text,c.name);
   if(c.read)assert.equal(actual.read,c.expected,c.name);
   if(c.noScroll)assert.deepEqual({x:actual.x,y:actual.y,pane:actual.pane},before,c.name);
   else if(!c.reject && !c.observeOnly && !c.inventoryOnly)assert.notDeepEqual({x:actual.x,y:actual.y,pane:actual.pane},before,'A successful offscreen action must actually scroll');
   if(c.nested)assert(actual.pane>0,c.name);
   if(c.hook)assert.equal(actual.hookRuns,1,'The scrolling mutation must actually run');
   rows.push({name:c.name,passed:true,outcome:result?.outcome??null,actual});
  }catch(error){rows.push({name:c.name,passed:false,error:error.message,result,actual,observation});}
 }
 const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
 const report={scope:'Generic authored offscreen layouts, actual isolated controller and DOM effects in disposable offline Chrome. No app, microphone, personal profile, screenshot or language model; real rendering events; behavior test, not a latency benchmark.',passed:rows.filter(r=>r.passed).length,total:rows.length,browser:browser.version.product,sourceSHA256:{controller:sha(sourcePath),test:sha(__filename),headless:sha(path.join(__dirname,'headless.cjs'))},rows};
 if(output)fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({passed:report.passed,total:report.total,failures:rows.filter(r=>!r.passed).map(r=>({name:r.name,error:r.error,result:r.result,actual:r.actual}))},null,2));
 if(report.passed!==report.total)process.exitCode=1;
}finally{await browser.close();}})().catch(error=>{console.error(error);process.exitCode=1});
