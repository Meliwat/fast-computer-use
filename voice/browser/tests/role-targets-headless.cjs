// Exact browser target resolution, without a language model or personal browser.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {Headless}=require('./headless.cjs');
const args=process.argv.slice(2),out=args.includes('--output')?args[args.indexOf('--output')+1]:null;
if(out&&fs.existsSync(out))throw Error('Choose a new report path');
const controllerPath=path.join(__dirname,'../extension/controller.js'),controller=fs.readFileSync(controllerPath,'utf8');
const widget=(id,role,label='Notifications')=>role==='native-checkbox'?`<label>${label}<input id="${id}" type="checkbox"></label>`:role==='native-radio'?`<label>${label}<input id="${id}" type="radio"></label>`:role==='native-button'?`<button id="${id}">${label}</button>`:role==='summary'?`<details><summary id="${id}">${label}</summary>Visible</details>`:role==='field'?`<input id="${id}" aria-label="${label}">`:`<div id="${id}" role="${role}" tabindex="0">${label}</div>`;
const cases=[];
for(const [role,word] of [['button','button'],['link','link'],['checkbox','checkbox'],['switch','switch'],['radio','radio button'],['option','option'],['tab','tab'],['menuitem','menu item'],['menuitemcheckbox','menu item'],['menuitemradio','menu item'],['native-checkbox','checkbox'],['native-radio','radio button'],['native-button','button'],['summary','button']]){
 const wrong=role==='link'?'button':'link';
 cases.push({name:role+' matching type',target:`Notifications ${word}`,html:widget('wanted',role),selected:'wanted'});
 cases.push({name:role+' wrong type',target:`Notifications ${wrong}`,html:widget('wrong',role),selected:null});
}
for(const word of ['button','link','checkbox','switch','tab','option'])cases.push({name:'same label / '+word,target:`Notifications ${word}`,html:['button','link','checkbox','switch','tab','option'].map(r=>widget(r,r)).join(''),selected:word});
cases.push(
 {name:'unqualified duplicates refuse',target:'Notifications',html:widget('a','button')+widget('b','link'),selected:null},
 {name:'leading type',target:'the link called Notifications',html:widget('wanted','link')+widget('wrong','button'),selected:'wanted'},
 {name:'leading type label is role noun',target:'the link named Button',html:widget('wanted','link','Button')+widget('wrong','button','Button'),selected:'wanted'},
 {name:'labelled type',target:'the checkbox labelled Notifications',html:widget('wanted','checkbox'),selected:'wanted'},
 {name:'extra whitespace',target:'Notifications radio   button',html:widget('wanted','radio'),selected:'wanted'},
 {name:'punctuated wrong type',target:'Notifications link,',html:widget('wrong','checkbox'),selected:null},
 {name:'literal suffix',target:'Help link',html:widget('wanted','button','Help link'),selected:'wanted'},
 {name:'literal suffix beats alternate role reading',target:'Help link',html:widget('wanted','button','Help link')+widget('wrong','link','Help'),selected:'wanted'},
 {name:'literal prefix',target:'link called Help',html:widget('wanted','button','link called Help')+widget('wrong','link','Help'),selected:'wanted'},
 {name:'standalone role noun label',target:'Switch',html:widget('wanted','button','Switch'),selected:'wanted'},
 {name:'role word in label',target:'Radio settings button',html:widget('wanted','button','Radio settings'),selected:'wanted'},
 {name:'role noun does not name another control',target:'Notifications link',html:widget('wanted','link')+widget('wrong','link','Link'),selected:'wanted'},
 {name:'role noun cannot retarget missing name',target:'Notifications link',html:widget('wrong','checkbox')+widget('other','link','Link'),selected:null},
 {name:'disabled matching role does not retarget homonym',target:'Notifications link',html:widget('wrong','link').replace('tabindex="0"','tabindex="0" aria-disabled="true"')+widget('other','button'),selected:null},
 {name:'unrelated disabled role does not block',target:'Notifications link',html:widget('wanted','link')+widget('other','button').replace('tabindex="0"','tabindex="0" aria-disabled="true"'),selected:'wanted'},
 {name:'scoped role target',target:'Notifications checkbox in Billing section',html:`<section aria-label="Billing">${widget('wanted','checkbox')}${widget('wrong','link')}</section><section aria-label="Profile">${widget('other','checkbox')}</section>`,selected:'wanted'},
 {name:'type changed after observation',target:'Notifications checkbox',html:widget('wanted','native-checkbox'),selected:'wanted',mutate:"document.querySelector('#wanted').type='radio'",dispatchReject:true},
 {name:'new literal reading invalidates bound type',target:'Help link',html:widget('wanted','link','Help'),selected:'wanted',mutate:`document.body.insertAdjacentHTML('beforeend',${JSON.stringify(widget('new','button','Help link'))})`,dispatchReject:true},
 {name:'new matching type duplicate invalidates binding',target:'Notifications checkbox',html:widget('wanted','checkbox'),selected:'wanted',mutate:`document.body.insertAdjacentHTML('beforeend',${JSON.stringify(widget('new','checkbox'))})`,dispatchReject:true},
 {name:'scoped literal priority ignores outside labels',target:'Help link in Billing section',html:`<section aria-label="Billing">${widget('wanted','link','Help')}</section>${widget('other','button','Help link')}`,selected:'wanted'},
 {name:'hidden literal does not change visible target',target:'Help link',html:widget('wanted','link','Help')+widget('other','button','Help link').replace('tabindex="0"','tabindex="0" hidden'),selected:'wanted'},
 {name:'disabled literal is not another reading',target:'Help link',html:widget('other','button','Help link').replace('tabindex="0"','tabindex="0" aria-disabled="true"')+widget('wrong','link','Help'),selected:null},
 {name:'wrong named type cannot retarget related label',target:'Notifications link',html:widget('wrong','checkbox')+widget('other','link','Notifications settings'),selected:null},
 {name:'exact typed name precedes related label',target:'Notifications button',html:widget('wanted','button')+widget('other','button','Notifications settings'),selected:'wanted'},
 {name:'disabled exact typed name blocks related label',target:'Notifications link',html:widget('wrong','link').replace('tabindex="0"','tabindex="0" aria-disabled="true"')+widget('other','link','Notifications settings'),selected:null},
 {name:'noninteractive literal cannot steal role hint',target:'Help link',html:widget('wanted','link','Help')+'<dialog open aria-label="Help link" style="position:fixed;left:600px;top:200px;width:100px">About</dialog>',selected:'wanted'},
 {name:'empty prefix name refuses',target:'link called',html:widget('wrong','link','Link'),selected:null},
 {name:'field role preserves literal label',target:'Search field',html:widget('wanted','field','Search field'),selected:'wanted',focus:true},
 {name:'field role distinguishes homonym button',target:'Search field',html:widget('wanted','field','Search')+widget('wrong','button','Search'),selected:'wanted',focus:true},
 {name:'field type cannot select a button',target:'Search field',html:widget('wrong','button','Search'),selected:null},
);
(async()=>{const b=new Headless({virtualTime:true}),rows=[];try{
 await b.start();
 for(const c of cases){
  let observation,result,actual;
  try{
   await b.evaluate(`document.body.innerHTML=${JSON.stringify(c.html)};globalThis.actions=[];for(const el of document.querySelectorAll('[id]'))el.addEventListener('click',()=>actions.push(el.id));`);await b.controller(controller);
   observation=(await b.run('observe',{target:c.target})).observation;
   const eligible=observation.candidates.filter(x=>x.enabled&&x.clickable);
   // Match the app's read-only exact preflight: dispatch only a unique observed identity.
   if(eligible.length===1){
    if(c.mutate)await b.evaluate(c.mutate);
    result=await b.run('click',{targetId:eligible[0].id,documentId:observation.documentId,observationId:observation.observationId});
   }
   actual=await b.evaluate('({actions,focused:document.activeElement.id})');
   const expected=c.selected&&!c.dispatchReject&&!c.focus?[c.selected]:[];
   assert.deepEqual(actual.actions,expected,c.name);
   if(c.focus)assert.equal(actual.focused,c.selected,c.name);
   if(c.dispatchReject)assert.equal(result?.ok,false,c.name);
   if(c.selected&&!c.dispatchReject)assert.equal(result?.ok,true,c.name);
   rows.push({name:c.name,passed:true,target:c.target,expected:c.selected,...actual,outcome:result?.outcome ?? null});
  }catch(e){rows.push({name:c.name,passed:false,target:c.target,error:e.message,actual,observation,result});}
 }
 const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
 const report={scope:'Generic authored role requests, actual controller in disposable offline Chrome; exact preflight + bound dispatch; no language model, speech or personal UI. Target identity/focus oracle, not generic task completion or latency.',passed:rows.filter(r=>r.passed).length,total:rows.length,rows,sourceSHA256:{controller:sha(controllerPath),test:sha(__filename),headless:sha(path.join(__dirname,'headless.cjs'))}};
 if(out)fs.writeFileSync(out,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({passed:report.passed,total:report.total,failures:rows.filter(r=>!r.passed).map(r=>({name:r.name,actual:r.actual,error:r.error}))},null,2));
 if(report.passed!==report.total)process.exitCode=1;
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
