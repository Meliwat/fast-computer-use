let port;
let chain=Promise.resolve();
let reconnectTimer;
function connect() {
  if(port) return;
  port=chrome.runtime.connectNative('dev.localvoice.browser');
  const connection=port;
  port.onDisconnect.addListener(()=>{
    // Consume Chrome's disconnect error and reconnect without user interaction.
    const reason=chrome.runtime.lastError?.message || 'Native connection closed';
    chrome.action.setTitle({title:'Local Voice: '+reason});
    port=null;
    chrome.action.setBadgeText({text:'!'});
    clearTimeout(reconnectTimer);
    reconnectTimer=setTimeout(connect,1500);
  });
  chrome.action.setBadgeText({text:''});
  chrome.action.setTitle({title:'Local Voice · automatic website control'});
  port.onMessage.addListener(message=>{
    chain=chain.catch(()=>{}).then(async()=>{
      let result;
      try { result=await execute(message.request); }
      catch(error) { result={ok:false,error:error.message}; }
      try { connection.postMessage({id:message.id,result}); } catch {}
    });
  });
}
chrome.action.onClicked.addListener(connect);
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
// Start the native host as soon as the extension worker starts.
connect();
async function execute(request) {
  if(!request || Date.now()>request.deadline) throw Error('Command expired');
  const window=await chrome.windows.getLastFocused();
  if(!window.focused) throw Error('Chrome is not the foreground app');
  const tabs=await chrome.tabs.query({active:true,windowId:window.id});
  const tab=tabs[0];
  if(!tab?.id) throw Error('No active tab');
  if(['newTab','nextTab','previousTab'].includes(request.op)) {
    if(request.op==='newTab') await chrome.tabs.create({windowId:window.id});
    else {
      const all=await chrome.tabs.query({windowId:window.id}); all.sort((a,b)=>a.index-b.index);
      const current=all.findIndex(t=>t.id===tab.id), step=request.op==='nextTab'?1:-1;
      await chrome.tabs.update(all[(current+step+all.length)%all.length].id,{active:true});
    }
    return {ok:true,message:'Tab action requested'};
  }
  if(!/^https?:/.test(tab.url||'')) throw Error('Voice page actions work on ordinary websites, not Chrome internal pages');
  // Injection is idempotent, survives same-origin navigation, and runs in the isolated world.
  await chrome.scripting.executeScript({target:{tabId:tab.id},files:['controller.js']});
  const [current]=await chrome.tabs.query({active:true,windowId:window.id});
  if(current?.id!==tab.id || current.url!==tab.url) throw Error('Active tab changed');
  const response=await chrome.scripting.executeScript({target:{tabId:tab.id},func:request=>globalThis.LocalVoiceDOM.runVerified(request),args:[{...request,expectedURL:tab.url}]});
  if(!response[0]?.result) throw Error('Page navigated before acknowledgement; not retrying');
  return response[0].result;
}
