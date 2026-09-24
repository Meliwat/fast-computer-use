// Real Chrome editing engine in an isolated headless profile. No user tabs/account/network.
const {spawn}=require('node:child_process');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const assert=require('node:assert/strict');
const profile=fs.mkdtempSync(path.join(os.tmpdir(),'localvoice-editor-'));
const binary=process.env.VOICE_TEST_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const child=spawn(binary,['--headless=new','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-sync','--use-mock-keychain','--password-store=basic','--remote-debugging-pipe',`--user-data-dir=${profile}`,'about:blank'],{stdio:['ignore','ignore','ignore','pipe','pipe']});
let sequence=0,buffer='',session;
const pending=new Map();
child.stdio[4].on('data',data=>{
  buffer+=data.toString();let end;
  while((end=buffer.indexOf('\0'))>=0){
    const message=JSON.parse(buffer.slice(0,end));buffer=buffer.slice(end+1);
    const item=pending.get(message.id);if(!item)continue;
    pending.delete(message.id);clearTimeout(item.timer);
    if(message.error)item.reject(Error(message.error.message));else item.resolve(message.result);
  }
});
function call(method,params={},sessionId){
  const id=++sequence;
  return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{pending.delete(id);reject(Error(`Timed out: ${method}`));},8000);
    pending.set(id,{resolve,reject,timer});
    child.stdio[3].write(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})})+'\0');
  });
}
async function evaluate(expression){
  const result=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true},session);
  if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
const source=fs.readFileSync(path.join(__dirname,'../extension/controller.js'),'utf8');
async function fixture(html){
  await evaluate(`globalThis.LocalVoiceDOM?.dispose();delete globalThis.LocalVoiceDOM;document.body.innerHTML=${JSON.stringify(html)};`);
  // about:blank lacks the secure-context UUID API; supply identities only.
  await evaluate(`if(!crypto.randomUUID){let n=0;crypto.randomUUID=()=> 'fixture-'+Date.now()+'-'+(++n);}`);
  await evaluate(source);
}
async function run(op,rest={}){
  return evaluate(`LocalVoiceDOM.runVerified({...${JSON.stringify({op,...rest})},expectedURL:location.href,deadline:Date.now()+1800})`);
}
(async()=>{
  try {
    const {targetId}=await call('Target.createTarget',{url:'about:blank'});
    ({sessionId:session}=await call('Target.attachToTarget',{targetId,flatten:true}));
    await call('Network.enable',{},session);
    await call('Network.setBlockedURLs',{urls:['*']},session);
    await call('Emulation.setFocusEmulationEnabled',{enabled:true},session);
    await fixture('<div contenteditable="true" role="textbox" aria-label="Post text" style="width:400px;min-height:60px">Hello friend</div><button>Post</button>');
    await evaluate(`globalThis.modelText='Hello friend';globalThis.posts=0;const editor=document.querySelector('[contenteditable]');editor.addEventListener('input',event=>{if(event.isTrusted)globalThis.modelText=editor.textContent});document.querySelector('button').onclick=()=>posts++;editor.focus();const range=document.createRange();range.setStart(editor.firstChild,6);range.setEnd(editor.firstChild,12);getSelection().removeAllRanges();getSelection().addRange(range);`);
    const typed=await run('type',{value:'world'});
    assert.equal(typed.ok,true,typed.error);
    assert.equal(await evaluate('modelText'),'Hello world','The editing engine did not notify the application model');
    assert.equal(await evaluate('posts'),0,'Typing must not submit');
    console.log('PASS: real rich-text selection replacement updates the application through trusted input, with no submit');
  } finally {
    try{await call('Browser.close');}catch{}
    if(child.exitCode===null)await new Promise(resolve=>{const timer=setTimeout(()=>{child.kill('SIGKILL');resolve();},2000);child.once('exit',()=>{clearTimeout(timer);resolve();});});
    fs.rmSync(profile,{recursive:true,force:true});
  }
})().catch(error=>{console.error(error.message);process.exitCode=1;});
