// Matched local disclosure fixture; alternating controllers, no user browser.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {Headless}=require('./headless.cjs');
const args=process.argv.slice(2),option=name=>{const i=args.indexOf(name);return i<0?null:args[i+1];};
const baseline=option('--baseline'),output=option('--output');
if(!baseline || !output)throw Error('Pass --baseline /path/to/old-controller.js --output /path/to/new-report.json');
const sources={baseline:fs.readFileSync(baseline,'utf8'),current:fs.readFileSync(path.join(__dirname,'../extension/controller.js'),'utf8')};
const sha=source=>crypto.createHash('sha256').update(source).digest('hex');
const samples={baseline:[],current:[]};
const quantile=(a,p)=>[...a].sort((x,y)=>x-y)[Math.ceil(a.length*p)-1];
(async()=>{const browser=new Headless();try{
  await browser.start();
  for(let index=0;index<22;index++){
    for(const arm of index%2?['current','baseline']:['baseline','current']){
      await browser.evaluate('document.body.innerHTML="<button aria-expanded=false>Options</button>";globalThis.clicks=0;(()=>{const button=document.querySelector("button");button.onclick=()=>{clicks++;button.setAttribute("aria-expanded","true")};})()');
      await browser.controller(sources[arm]);
      const result=await browser.run('click',{target:'Options'});
      assert.equal(result.outcome,'verified');assert.equal(await browser.evaluate('clicks'),1);
      assert.equal(await browser.evaluate('document.querySelector("button").getAttribute("aria-expanded")'),'true');
      if(index>=2)samples[arm].push(result.totalMs);
    }
  }
  const report={scope:'One synthetic stable aria-expanded button in isolated headless Chrome. Twenty measured samples per controller, alternating arm order; two excluded warmups per arm. Controller observation/dispatch/verification time only, excludes fixture setup, IPC, speech, model parsing, extension/native host and real sites.',browser:browser.version.product,sourceSHA256:Object.fromEntries(Object.entries(sources).map(([key,value])=>[key,sha(value)])),samples,metrics:Object.fromEntries(Object.entries(samples).map(([key,values])=>[key,{n:values.length,medianMs:quantile(values,.5),p95Ms:quantile(values,.95)}]))};
  fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify(report.metrics,null,2));
}finally{await browser.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
