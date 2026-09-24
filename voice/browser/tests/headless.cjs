// Dedicated headless Chrome, private CDP pipes, temporary profile, all page network blocked.
// Never attaches to an existing browser or reads a user's profile.
const {spawn}=require('node:child_process');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
class Headless {
  constructor({virtualTime=false}={}){this.pending=new Map();this.sequence=0;this.buffer='';this.virtualTime=virtualTime;}
  async start(){
    this.profile=fs.mkdtempSync(path.join(os.tmpdir(),'localvoice-headless-'));
    const binary=process.env.VOICE_TEST_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    this.child=spawn(binary,['--headless=new','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-sync','--use-mock-keychain','--password-store=basic','--remote-debugging-pipe',`--user-data-dir=${this.profile}`,'about:blank'],{stdio:['ignore','ignore','ignore','pipe','pipe']});
    this.child.on('error',error=>{for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(error);}this.pending.clear();});
    this.child.stdio[4].on('data',data=>{
      this.buffer+=data.toString();let end;
      while((end=this.buffer.indexOf('\0'))>=0){
        const message=JSON.parse(this.buffer.slice(0,end));this.buffer=this.buffer.slice(end+1);
        const p=this.pending.get(message.id);if(!p)continue;
        this.pending.delete(message.id);clearTimeout(p.timer);
        if(message.error)p.reject(Error(message.error.message));else p.resolve(message.result);
      }
    });
    const {targetId}=await this.call('Target.createTarget',{url:'about:blank'});
    this.session=(await this.call('Target.attachToTarget',{targetId,flatten:true})).sessionId;
    await this.call('Network.enable',{},true);
    await this.call('Network.setBlockedURLs',{urls:['*']},true);
    await this.call('Emulation.setFocusEmulationEnabled',{enabled:true},true);
    await this.call('Emulation.setDeviceMetricsOverride',{width:1280,height:900,deviceScaleFactor:1,mobile:false},true);
    const {frameTree}=await this.call('Page.getFrameTree',{},true);
    this.context=(await this.call('Page.createIsolatedWorld',{frameId:frameTree.frame.id,worldName:'LocalVoiceFixture',grantUniveralAccess:false},true)).executionContextId;
    this.version=await this.call('Browser.getVersion');
    if(this.virtualTime)await this.call('Emulation.setVirtualTimePolicy',{policy:'pause'},true);
    return this;
  }
  call(method,params={},page=false){
    const id=++this.sequence;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{this.pending.delete(id);reject(Error(`Timed out: ${method}`));},8000);
      this.pending.set(id,{resolve,reject,timer});
      this.child.stdio[3].write(JSON.stringify({id,method,params,...(page?{sessionId:this.session}:{})})+'\0');
    });
  }
  async evaluate(expression,isolated=false){
    const r=await this.call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true,...(isolated?{contextId:this.context}:{})},true);
    if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description || JSON.stringify(r.exceptionDetails));
    return r.result.value;
  }
  async controller(source){
    await this.evaluate(`globalThis.LocalVoiceDOM?.dispose();delete globalThis.LocalVoiceDOM;if(!crypto.randomUUID){let n=0;crypto.randomUUID=()=> 'fixture-'+Date.now()+'-'+(++n);}`,true);
    await this.evaluate(source,true);
  }
  async run(op,rest={}){
    const expression=`LocalVoiceDOM.runVerified({...${JSON.stringify({op,...rest})},expectedURL:location.href,deadline:Date.now()+2200})`;
    if(!this.virtualTime)return this.evaluate(expression,true);
    // Opt-in deterministic fixture timing. Benchmark callers keep the real clock.
    // Start the action while paused before advancing its page and verifier timers.
    try {
      const [result]=await Promise.all([
        this.evaluate(expression,true),
        this.call('Emulation.setVirtualTimePolicy',{policy:'advance',budget:1000},true),
      ]);
      return result;
    }finally{await this.call('Emulation.setVirtualTimePolicy',{policy:'pause'},true);}
  }
  async close(){
    try{if(this.child?.exitCode===null)await this.call('Browser.close');}catch{}
    if(this.child?.exitCode===null)await new Promise(resolve=>{
      const timer=setTimeout(()=>{this.child.kill('SIGKILL');resolve();},2000);
      this.child.once('exit',()=>{clearTimeout(timer);resolve();});
    });
    for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('Headless browser closed'));}this.pending.clear();
    if(this.profile)fs.rmSync(this.profile,{recursive:true,force:true,maxRetries:5,retryDelay:100});
  }
}
module.exports={Headless};
