const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../extension/background.js'),'utf8');
function setup() {
  const state={connections:0,injections:0,replies:[],url:'https://example.test/',focused:true};
  const event=()=>({addListener(fn){this.listener=fn;}});
  const port={onDisconnect:event(),onMessage:event(),postMessage(reply){state.replies.push(reply);}};
  const chrome={runtime:{connectNative(){state.connections++;return port;},onStartup:event(),onInstalled:event()},
    action:{onClicked:event(),setBadgeText(){},setTitle(){}},windows:{async getLastFocused(){return {id:1,focused:state.focused};}},
    tabs:{async query(){return [{id:3,url:state.url}];}},
    scripting:{async executeScript(options){state.injections++;return options.func?[{result:{ok:true,message:'test'}}]:[];}}};
  const context=vm.createContext({chrome,setTimeout,clearTimeout});vm.runInContext(source,context);
  return {state,context};
}
test('Connects without toolbar activation and operates across websites',async()=>{
  const {state,context}=setup();assert.equal(state.connections,1);
  for(const url of ['https://example.test/','https://another.test/']) {
    state.url=url;
    const result=await vm.runInContext('execute({op:"click",target:"Details",deadline:Date.now()+2000})',context);
    assert.equal(result.ok,true);
  }
  assert.equal(state.injections,4);
});
test('Rejects expired, background and internal-page requests',async()=>{
  const {state,context}=setup();
  await assert.rejects(vm.runInContext('execute({deadline:0})',context),/expired/);
  state.focused=false;
  await assert.rejects(vm.runInContext('execute({deadline:Date.now()+2000})',context),/foreground/);
  state.focused=true;state.url='chrome://extensions/';
  await assert.rejects(vm.runInContext('execute({deadline:Date.now()+2000})',context),/ordinary websites/);
  assert.equal(state.injections,0);
});
