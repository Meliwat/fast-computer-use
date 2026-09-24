// jsdom has no native editing engine. This narrow test double supports ordinary
// fields only; real Chromium + actual editor libraries test the production path.
module.exports=function installEditingStub(window){
  window.document.execCommand=(command,_ui,text)=>{
    if(command!=='insertText')return false;
    let el=window.document.activeElement;
    while(el?.shadowRoot?.activeElement)el=el.shadowRoot.activeElement;
    if(!(el instanceof window.HTMLInputElement || el instanceof window.HTMLTextAreaElement))return false;
    el.setRangeText(text,el.selectionStart,el.selectionEnd,'end');
    el.dispatchEvent(new window.InputEvent('input',{bubbles:true,composed:true,inputType:'insertText',data:text}));
    return true;
  };
};
