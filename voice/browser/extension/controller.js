/* Generic DOM actions plus a read-only X search demo verifier. No eval or network. */
(() => {
  if (globalThis.LocalVoiceDOM?.version === 16) return;
  globalThis.LocalVoiceDOM?.dispose?.();
  const documentId = crypto.randomUUID();
  const identities = new WeakMap();
  const observations = new Map();
  let nextID = 0, observationSequence = 0;
  const identity = el => {
    if (!el) return null;
    if (!identities.has(el)) identities.set(el, `${documentId}:${++nextID}`);
    return identities.get(el);
  };
  const normalize = s => String(s || '').normalize('NFKC').toLowerCase().trim().replace(/\s+/g, ' ');
  const ariaActions='[role=button],[role=link],[role=tab],[role=menuitem],[role=menuitemcheckbox],[role=menuitemradio],[role=checkbox],[role=switch],[role=radio],[role=option]';
  const nativeCheck = el => el instanceof HTMLInputElement && el.matches('input[type=checkbox],input[type=radio]');
  const controlRole = el => el.getAttribute('role') || (nativeCheck(el)?el.type:el.tagName.toLowerCase());
  const checkable = el => el.matches('input[type=checkbox],[role=checkbox],[role=switch],[role=menuitemcheckbox]');
  const checkedValue = el => nativeCheck(el) ? (el.indeterminate?'mixed':String(el.checked)) : el.getAttribute('aria-checked');
  const validChecked = (el,value) => {
    const role=el.getAttribute('role');
    const mixed=['checkbox','menuitemcheckbox'].includes(role) || (!role && el.matches('input[type=checkbox]'));
    return ['true','false',...(mixed?['mixed']:[])].includes(value);
  };
  function* ancestors(el) {
    for(let node=el;node instanceof Element;node=node.parentElement || node.getRootNode().host) yield node;
  }
  let cache = null, scopeCache = [], revision = 0, draft = null, pendingSearch = null;
  const scopeSelectors={section:'section,[role=region]',region:'section,[role=region]',panel:'section,[role=region]',group:'fieldset,[role=group]',form:'form,[role=form]',dialog:'dialog,[role=dialog]'};
  const scopeSelector=[...new Set(Object.values(scopeSelectors))].join(',');
  const observer = new MutationObserver(() => { cache = null; revision++; });
  observer.observe(document, {subtree:true, childList:true, attributes:true, characterData:true});
  const blocked = el => el.matches('input[type=password],input[type=file],input[type=hidden]') || [...ancestors(el)].some(node=>node.matches('[inert],[aria-hidden="true"]'));
  const painted = el => {
    if (!el.isConnected || !el.getClientRects().length) return false;
    const rect=el.getBoundingClientRect();
    if(rect.width<=0 || rect.height<=0 || rect.right<=0 || rect.bottom<=0 || rect.left>=innerWidth || rect.top>=innerHeight) return false;
    for(let node=el;node instanceof Element;node=node.parentElement || node.getRootNode().host) {
      const style=getComputedStyle(node);
      if(style.visibility==='hidden' || style.visibility==='collapse' || style.display==='none' || style.opacity==='0') return false;
    }
    return true;
  };
  const rendered = el => !blocked(el) && painted(el);
  const visible = el => {
    if(!rendered(el)) return false;
    const rect=el.getBoundingClientRect();
    if(typeof document.elementFromPoint==='function') {
      const x=(Math.max(0,rect.left)+Math.min(innerWidth,rect.right))/2,y=(Math.max(0,rect.top)+Math.min(innerHeight,rect.bottom))/2;
      let hit=document.elementFromPoint(x,y);
      for(let depth=0;hit?.shadowRoot && depth<8;depth++) {
        const next=hit.shadowRoot.elementFromPoint?.(x,y);if(!next || next===hit)break;hit=next;
      }
      if(!hit || !(hit===el || el.contains(hit))) return false;
    }
    return true;
  };
  const enabled = el => !el.matches(':disabled') && ![...ancestors(el)].some(node=>node.getAttribute('aria-disabled')==='true');
  function labelText(label) {
    if (!label) return '';
    const copy=label.cloneNode(true);
    copy.querySelectorAll('input,textarea,select,button').forEach(el=>el.remove());
    return copy.textContent;
  }
  function labels(el) {
    const root = el.getRootNode();
    const references = (el.getAttribute('aria-labelledby') || '').split(/\s+/).filter(Boolean).map(id => root.getElementById?.(id)?.textContent || '').join(' ');
    return [...new Set([references,el.getAttribute('aria-label'),...(el.labels || [])].map(x => typeof x === 'string' ? x : labelText(x))
      .concat([el.getAttribute('placeholder'),el.getAttribute('title'),el.matches('button,a,summary,'+ariaActions) ? el.textContent : '',el.matches('input[type=submit],input[type=button]') ? el.value : ''])
      .map(normalize).filter(Boolean))];
  }
  const editable = el => el && !blocked(el) && (el.matches('textarea,input:not([type]),input[type=text],input[type=search],input[type=email],input[type=url],input[type=tel],input[type=number],[role=textbox],[role=searchbox]') || el.isContentEditable);
  const detailsFor = el => el?.matches('summary') && el.parentElement?.matches('details') && [...el.parentElement.children].find(child=>child.matches('summary'))===el ? el.parentElement : null;
  const clickable = el => editable(el) || el.matches('button,a[href],input[type=submit],input[type=button],input[type=checkbox],input[type=radio],'+ariaActions) || !!detailsFor(el);
  function controls() {
    if (cache) return cache;
    const result = [], scopes = [], roots = [document];
    let examined = 0;
    while (roots.length) {
      const root = roots.pop();
      // One traversal discovers controls and open shadow roots without layout work.
      const walker = document.createTreeWalker(root,NodeFilter.SHOW_ELEMENT);
      let el;
      while ((el = walker.nextNode())) {
        if (++examined > 20000) throw Error('Page is too large for a bounded fast scan');
        if (el.shadowRoot) { roots.push(el.shadowRoot); observer.observe(el.shadowRoot,{subtree:true,childList:true,attributes:true,characterData:true}); }
        if (el.matches(scopeSelector)) scopes.push(el);
        if (el.matches('dialog,[role=dialog],button,input,textarea,select,a[href],summary,[role=textbox],[role=searchbox],[contenteditable]:not([contenteditable=false]),'+ariaActions)) result.push(el);
      }
    }
    scopeCache=scopes;cache = result; return result;
  }
  function chooseRequest(request, predicate) {
    if (!request.targetId) return choose(request.target, predicate);
    if (request.documentId !== documentId) throw Error('Target belongs to an older page');
    const el = controls().find(el => identity(el) === request.targetId);
    if (!el || !within(interactionScope(),el) || !predicate(el) || !visible(el) || !enabled(el)) throw Error('Target is no longer available');
    const recorded=observations.get(request.observationId)?.get(request.targetId);
    if(!recorded || recorded.signature!==signature(el)) throw Error('Target changed since observation; observe again');
    if(recorded.query) {
      const context=targetContext(recorded.query);
      if(context.scope!==recorded.scope || chooseWithin(context.target,predicate,context.scope)!==el) throw Error('Named scope changed since observation; observe again');
    }
    return el;
  }
  function matchesTarget(el,target) {
    const original=normalize(target),field=/\b(?:field|box|input|editor)$/.test(original);
    if(field && !editable(el)) return false;
    if(/\bbutton$/.test(original) && !el.matches('button,input[type=submit],input[type=button],[role=button]')) return false;
    if(/\blink$/.test(original) && !el.matches('a[href],[role=link]')) return false;
    const wanted=original.replace(/^the\s+/,'').replace(/\s+(?:text field|field|box|input|editor|button|link)$/,'').trim();
    if(labels(el).includes(original) || labels(el).includes(wanted)) return true;
    const words=wanted.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
    return words.length>0 && labels(el).some(label=>{
      const available=new Set(label.split(/[^\p{L}\p{N}]+/u).filter(Boolean));
      return words.every(word=>available.has(word));
    });
  }
  function choose(target, predicate) {
    const context=targetContext(target);
    return chooseWithin(context.target,predicate,context.scope);
  }
  function chooseWithin(target,predicate,scope) {
    const matches=controls().filter(el=>within(scope,el) && predicate(el) && matchesTarget(el,target) && visible(el) && enabled(el));
    if(matches.length!==1) throw Error(matches.length ? `More than one control matches “${target}”; name its field or button` : `No available control named “${target}”`);
    return matches[0];
  }
  function qualifiedTarget(target) {
    const match=normalize(target).match(/^(.+?)\s+in\s+(?:the\s+)?(.+?)\s+(section|region|panel|group|form|dialog)$/);
    return match?{target:match[1],name:match[2],kind:match[3]}:null;
  }
  function scopeName(el) {
    const references=el.getAttribute('aria-labelledby');
    let text;
    if(references!==null) {
      const ids=references.trim().split(/\s+/).filter(Boolean),root=el.getRootNode();
      if(!ids.length || ids.length>8) return null;
      const parts=[];
      for(const id of ids) {
        if(id.length>256) return null;
        const matches=root.querySelectorAll('#'+Array.from(id,c=>'\\'+c.codePointAt(0).toString(16)+' ').join(''));
        if(matches.length!==1)return null;
        parts.push(matches[0].textContent);
      }
      text=parts.join(' ');
    } else if(el.hasAttribute('aria-label')) text=el.getAttribute('aria-label');
    else {
      const children=[...el.children],heading='h1,h2,h3,h4,h5,h6,[role=heading]';
      const names=el.matches('fieldset')?children.filter(node=>node.matches('legend')):
        children.flatMap(node=>node.matches(heading)?[node]:node.matches('header')?[...node.children].filter(child=>child.matches(heading)):[]);
      if(names.length!==1 || !rendered(names[0]))return null;
      text=names[0].textContent;
    }
    const name=normalize(text);
    return name && name.length<=100?name:null;
  }
  function targetContext(target) {
    flush();
    const scope=interactionScope(),qualified=qualifiedTarget(target);
    if(!qualified)return {target,scope,qualified:false};
    const matches=scopeCache.filter(el=>within(scope,el) && el.matches(scopeSelectors[qualified.kind]) && scopeName(el)===qualified.name && rendered(el) && enabled(el));
    // Scope syntax must not turn a literal label such as “Open in side panel”
    // into a different action. Refuse when both readings are available.
    const literal=normalize(target).replace(/^the\s+/,''),literalMatch=controls().some(el=>within(scope,el) && (clickable(el) || el.matches('select')) && labels(el).includes(literal) && visible(el));
    if(literalMatch) {
      if(matches.length)throw Error('That phrase names both a control and a section; use a more specific target');
      return {target,scope,qualified:false};
    }
    if(matches.length!==1)throw Error(matches.length?`More than one named ${qualified.kind} matches “${qualified.name}”`:`No available ${qualified.kind} named “${qualified.name}”`);
    return {target:qualified.target,scope:matches[0],qualified:true};
  }
  function scopeBinding(request) {
    const recorded=request.targetId?observations.get(request.observationId)?.get(request.targetId):null;
    if(recorded?.query)return {query:recorded.query,scope:recorded.scope};
    if(!qualifiedTarget(request.target))return null;
    const context=targetContext(request.target);
    return context.qualified?{query:request.target,scope:context.scope}:null;
  }
  function recheckScopedTarget(request,el,binding) {
    if(!binding)return;
    const context=targetContext(binding.query);
    if(!context.qualified || context.scope!==binding.scope || targetFor(request)!==el)throw Error('Named target or section changed; action not repeated');
  }
  function within(scope,el) {
    for(let node=el;node;node=node.parentNode || node.host) if(node===scope) return true;
    return false;
  }
  function interactionScope() {
    const dialogs=controls().filter(el=>(el.matches('[role=dialog][aria-modal=true],dialog[aria-modal=true]') || (el.matches('dialog[open]') && el.matches(':modal'))) && visible(el));
    // Nested dialogs use the innermost active layer; unrelated simultaneous dialogs are ambiguous.
    const leaves=dialogs.filter(el=>!dialogs.some(other=>other!==el && within(el,other)));
    if(leaves.length>1) throw Error('More than one dialog is open; close one before continuing');
    return leaves[0] || document;
  }
  function typingField(request) {
    if(request.targetId || request.target) {
      const field=chooseRequest(request,editable);
      if(request.targetId && active()!==field) throw Error('The verified field lost focus; no text sent');
      return field;
    }
    const current=active(),scope=interactionScope();
    if(within(scope,current) && current?.matches('input[type=password],iframe')) throw Error('The focused protected field or frame cannot receive dictation');
    if(within(scope,current) && editable(current)) {
      if(!visible(current) || !enabled(current) || current.readOnly) throw Error('The focused field is not editable');
      return current;
    }
    const fields=controls().filter(el=>within(scope,el) && editable(el) && visible(el) && enabled(el) && !el.readOnly);
    const editors=fields.filter(el=>el.isContentEditable || el.matches('textarea,[aria-multiline=true]'));
    if(editors.length===1) return editors[0];
    if(fields.length===1) return fields[0];
    throw Error(fields.length?'Several text fields are available; say “click the Message field”, then dictate':'No editable field is visible');
  }
  function active() {
    let el = document.activeElement;
    while (el?.shadowRoot?.activeElement) el = el.shadowRoot.activeElement;
    return el;
  }
  function value(el) { return el.isContentEditable ? el.textContent : el.value; }
  function focusField(el) {
    if(!editable(el) || !visible(el) || !enabled(el) || el.readOnly) throw Error('Field is not editable');
    el.focus({preventScroll:true});
    if(active()!==el) throw Error('Field did not receive focus');
    if(el.isContentEditable) {
      const selection=el.getRootNode().getSelection?.() || document.getSelection();
      if(!selection?.rangeCount || !el.contains(selection.anchorNode) || !el.contains(selection.focusNode)) {
        const range=document.createRange();range.selectNodeContents(el);range.collapse(false);
        selection.removeAllRanges();selection.addRange(range);
      }
    }
  }
  function fill(el, text, insert = false, recheck = null) {
    if(typeof text!=='string' || text.length>16000) throw Error('Text is too long');
    if(typeof document.execCommand!=='function') throw Error('Browser editing engine unavailable; no text sent');
    focusField(el);
    recheck?.();
    let expected;
    if(el.isContentEditable) {
      const selection=el.getRootNode().getSelection?.() || document.getSelection();
      const range=insert ? selection.getRangeAt(0) : document.createRange();
      if(!insert){range.selectNodeContents(el);selection.removeAllRanges();selection.addRange(range);}
      if(!el.contains(range.startContainer) || !el.contains(range.endContainer)) throw Error('Selection left the intended editor');
      const prefix=document.createRange();prefix.selectNodeContents(el);prefix.setEnd(range.startContainer,range.startOffset);
      const suffix=document.createRange();suffix.selectNodeContents(el);suffix.setStart(range.endContainer,range.endOffset);
      expected=prefix.toString()+text+suffix.toString();
    }else{
      const old=el.value;
      if(!insert) el.select();
      const start=insert?el.selectionStart:0,end=insert?el.selectionEnd:old.length;
      if(insert && (start==null || end==null)) throw Error('Field does not expose a text cursor; use fill with its name');
      expected=old.slice(0,start)+text+old.slice(end);
    }
    // Browser editing, not DOM replacement: preserves editor structure, undo and native input events.
    // Never follow a refused or uncertain edit with another insertion method.
    if(active()!==el || !document.execCommand('insertText',false,text)) throw Error('Editor refused text; not retrying');
    const normalizeBreaks=s=>String(s).replace(/[\r\n]/g,'');
    if(normalizeBreaks(value(el))!==normalizeBreaks(expected)) throw Error('Editor text differs from the requested insertion; not retrying');
    draft={el,value:value(el)};
  }
  function searchField() {
    const scope=interactionScope();
    const fields = controls().filter(el => within(scope,el) && editable(el) && visible(el) && enabled(el) && !el.readOnly && (el.matches('input[type=search],[role=searchbox]') || labels(el).some(s => /\bsearch\b/.test(s))));
    if (fields.length !== 1) throw Error(fields.length ? 'More than one search field; use “fill … with …”' : 'No available search field');
    return fields[0];
  }
  function exactTextTarget(target, writable) {
    if(typeof target!=='string' || !target.trim() || target.length>100 || /[\u0000-\u001f\u007f]/.test(target)) throw Error('Name one text field');
    flush();
    const context=targetContext(target),scope=context.scope,raw=normalize(context.target),stripped=raw.replace(/^the\s+/,'').replace(/\s+(?:text field|text box|field|input|editor)$/,'');
    const fields=controls().filter(el=>within(scope,el) && editable(el) && visible(el));
    for(const wanted of [...new Set([raw,stripped])]) {
      const matches=fields.filter(el=>labels(el).some(label=>label.replace(/\s*:\s*$/,'')===wanted));
      if(!matches.length) continue;
      if(matches.length!==1 || !enabled(matches[0]) || writable && matches[0].readOnly) throw Error(`Could not identify one available field named “${target}”`);
      return matches[0];
    }
    throw Error(`No available text field named “${target}”`);
  }
  async function runExistingText(request,commandId,started) {
    let wrote=false;
    try {
      if(request.targetId || request.observationId || request.documentId && request.documentId!==documentId) throw Error('Existing-text operation requires current named fields');
      const copying=request.op==='copyText';
      if(copying ? request.value!=null : !['uppercase','lowercase'].includes(request.value) || request.source!=null) throw Error('Invalid existing-text operation');
      const sourceName=copying?request.source:request.target;
      const source=exactTextTarget(sourceName,false),target=exactTextTarget(request.target,true);
      const sourceScope=targetContext(sourceName).scope,targetScope=targetContext(request.target).scope;
      const read=field=>field.isContentEditable?field.innerText:value(field);
      const original=read(source),before=read(target),sourceSignature=signature(source),targetSignature=signature(target);
      if(typeof original!=='string' || typeof before!=='string' || original.length>16000 || before.length>16000) throw Error('The field text is unavailable or too long');
      const expected=copying?original:request.value==='uppercase'?original.toUpperCase():original.toLowerCase();
      if(expected.length>16000) throw Error('The resulting text is too long');
      if(target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) {
        const probe=target.cloneNode(false);probe.value=expected;
        if(probe.value!==expected || target.maxLength>=0 && expected.length>target.maxLength) throw Error('The destination cannot preserve that text; no text sent');
      }
      const sameFields=()=>targetContext(sourceName).scope===sourceScope && targetContext(request.target).scope===targetScope && exactTextTarget(sourceName,false)===source && exactTextTarget(request.target,true)===target;
      checkContext(request);draft=null;pendingSearch=null;
      focusField(target);
      checkContext(request);
      if(!sameFields() || read(source)!==original || read(target)!==before || signature(source)!==sourceSignature || signature(target)!==targetSignature) throw Error('Source or destination changed before editing; no text sent');
      if(before!==expected) {wrote=true;fill(target,expected);}
      draft=null;
      const verifyStart=performance.now();
      do {
        checkContext(request);
        if(!sameFields() || active()!==target || read(target)!==expected || source!==target && (read(source)!==original || signature(source)!==sourceSignature)) throw Error('Source or destination changed; action not repeated');
        if(performance.now()-verifyStart>=180) break;
        await new Promise(resolve=>setTimeout(resolve,30));
      } while(true);
      return {ok:true,commandId,outcome:'verified',message:before===expected?'Field already matches · text verified':copying?'Field copied · text verified':`Text made ${request.value} · verified`,documentId,targetId:identity(target),sourceId:identity(source),totalMs:performance.now()-started};
    } catch(error) {
      draft=null;
      return {ok:false,commandId,outcome:wrote?'unverified':'failed',error:error.message};
    }
  }
  function searchSubmissionAllowed(el) {
    const form=el.form || el.closest('form');
    if(!form) return;
    // Native Enter can activate the form's default submitter. Refuse unrelated actions.
    const submitters=[...form.elements].filter(x=>x.matches('button,input') && x.type==='submit' && enabled(x));
    if(submitters.some(x=>!labels(x).some(label=>/\bsearch\b/.test(label)))) throw Error('Search shares a form with an unrelated submit action; focus a dedicated search field');
  }
  // Demo-specific evidence only; no site-specific dispatch or generated selectors.
  function xSearchEvidence(query) {
    const supported=['x.com','www.x.com','twitter.com','www.twitter.com'].includes(location.hostname);
    const empty={supported,queryMatches:false,loaded:false,signature:'',documentId,visibleResults:0};
    if(!supported || typeof query!=='string' || !query.trim()) return empty;
    const fields=[...document.querySelectorAll('input[role=combobox][aria-label="Search query"]')].filter(visible);
    const url=new URL(location.href),queries=url.searchParams.getAll('q');
    const queryMatches=url.pathname==='/search' && queries.length===1 && queries[0]===query && fields.length===1 && fields[0].value===query;
    const regions=[...document.querySelectorAll('[role=region]')].filter(el=>labels(el).includes('search timeline'));
    const region=regions.length===1?regions[0]:null;
    const scope=region || document.querySelector('main') || document;
    const articles=[...scope.querySelectorAll('article')].slice(0,32).filter(visible);
    const links=[...new Set(articles.flatMap(el=>[...el.querySelectorAll('a[href*="/status/"]')].map(a=>a.getAttribute('href'))))].sort();
    const tabs=[...document.querySelectorAll('[role=tab][aria-selected=true]')].filter(visible);
    const postsTab=tabs.length===1 && labels(tabs[0]).some(label=>['top','latest'].includes(label));
    const loading=!!region && (region.closest('[aria-busy=true]') || [...region.querySelectorAll('[role=progressbar],[aria-busy=true]')].some(visible));
    return {supported,queryMatches,documentId,signature:links.join('|').slice(0,8192),visibleResults:articles.length,
      loaded:!!region && visible(region) && postsTab && !loading && articles.length>0 && links.length>0};
  }
  function checkContext(request) {
    if (request.expectedURL !== location.href) throw Error('Page changed before the action');
    if (!document.hasFocus()) throw Error('Tab lost focus; no action sent');
    if (!Number.isFinite(request.deadline) || Date.now() > request.deadline) throw Error('Command expired; no action sent');
  }
  function run(request) {
    const start = performance.now();
    try {
      checkContext(request);
      if (observer.takeRecords().length) { cache = null; revision++; }
      const before = revision;
      let message;
      switch (request.op) {
        case 'capabilities': return {ok:true,protocolVersion:2,verifiedDispatch:false,message:'Direct dispatcher'};
        case 'observe': return {ok:true,observation:observe(request.target),message:'Page observed'};
        case 'prepareSearch': { const el=searchField(); pendingSearch=null; searchSubmissionAllowed(el); checkContext(request); fill(el,request.value); draft=null; message='Search query prepared'; break; }
        case 'fill': { const el = chooseRequest(request,editable),binding=scopeBinding(request); checkContext(request); fill(el,request.value,false,()=>recheckScopedTarget(request,el,binding)); message='Field filled and read back'; break; }
        case 'type': { const el=typingField(request),binding=scopeBinding(request); checkContext(request); fill(el,request.value,true,()=>recheckScopedTarget(request,el,binding)); message='Draft inserted · say send it to submit'; break; }
        case 'click': { const el=chooseRequest(request,clickable); checkContext(request); draft=null; if(editable(el)) { focusField(el); message='Field focused'; } else { el.click(); message='Click requested'; } break; }
        case 'select': {
          const el=chooseRequest(request,el=>el instanceof HTMLSelectElement);
          const options=[...el.options].filter(o=>!o.disabled && normalize(o.label)===normalize(request.value));
          if (options.length!==1) throw Error('Could not identify one matching option');
          checkContext(request); el.value=options[0].value;
          el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true}));
          if(el.value!==options[0].value) throw Error('Selection changed during the action');
          draft=null; message='Selection verified'; break;
        }
        case 'check': {
          const el=chooseRequest(request,checkable),current=checkedValue(el);
          if(typeof request.checked!=='boolean') throw Error('A check command requires a requested boolean state');
          if(!validChecked(el,current)) throw Error('The control does not expose a valid checked state');
          checkContext(request); if(current!==String(request.checked)) el.click();
          if(checkedValue(el)!==String(request.checked)) throw Error('Checkable control change not verified');
          draft=null; message='Checkable control state verified'; break;
        }
        case 'search': {
          const el=searchField(), form=el.form || el.closest('form');
          if (!form) throw Error('Search field has no form; fill it and click its search control');
          const buttons=[...form.querySelectorAll('button,input[type=submit]')].filter(b=>enabled(b)&&visible(b)&&labels(b).some(s=>/\bsearch\b/.test(s)));
          if(buttons.length>1) throw Error('Search has multiple submit buttons');
          if(!buttons.length && !el.matches('input[type=search]') && form.getAttribute('role')!=='search') throw Error('Could not identify the search submission');
          checkContext(request); fill(el,request.value); draft=null;
          if(buttons.length) buttons[0].click(); else HTMLFormElement.prototype.requestSubmit.call(form);
          message='Search submitted'; break;
        }
        case 'send': {
          if(!draft || !draft.el.isConnected || active()!==draft.el || value(draft.el)!==draft.value) throw Error('No unchanged dictated draft is focused');
          const scope=draft.el.form || draft.el.closest('[role=dialog]') || document;
          const matches=controls().filter(el=>scope.contains(el)&&clickable(el)&&visible(el)&&enabled(el)&&labels(el).some(s=>['send','send message','send prompt','submit prompt'].includes(s)));
          if(matches.length!==1) throw Error('Could not identify one Send control');
          checkContext(request); draft=null; matches[0].click(); message='Send requested'; break;
        }
        case 'scroll':
          checkContext(request); { const el=scrollTarget(); el.scrollBy({top:(request.value==='up'?-1:1)*scrollHeight(el)*0.8,behavior:'instant'}); } message='Scroll requested'; break;
        default: throw Error('Unsupported browser action');
      }
      if(observer.takeRecords().length) { cache=null; revision++; }
      return {ok:true,message,domChanged:revision!==before,domMs:performance.now()-start};
    } catch(error) { return {ok:false,error:error.message,domMs:performance.now()-start}; }
  }

  function scrollHeight(el) {
    return Math.max(1,el===document.documentElement || el===document.body || el===document.scrollingElement ? innerHeight : el.clientHeight || el.getBoundingClientRect().height);
  }
  function scrollTarget() {
    const scrollable = el => el && el.scrollHeight > scrollHeight(el) + 1;
    const scope=interactionScope();
    if(scope!==document) {
      for(let el=active();el && within(scope,el);el=el.parentElement) {
        if(scrollable(el) && /auto|scroll/.test(getComputedStyle(el).overflowY)) return el;
      }
      const candidates=[scope,...scope.querySelectorAll('*')].filter(el=>visible(el)&&scrollable(el)&&/auto|scroll/.test(getComputedStyle(el).overflowY));
      if(candidates.length>1) throw Error('Focus the dialog area you want to scroll');
      return candidates[0] || scope;
    }
    for (let el=active(); el && el!==document.body; el=el.parentElement) {
      if (scrollable(el) && /auto|scroll/.test(getComputedStyle(el).overflowY)) return el;
    }
    const root=document.scrollingElement || document.documentElement;
    if(scrollable(root)) return root;
    const containers=[...document.querySelectorAll('main,section,div,[role=region]')].filter(el=>visible(el)&&scrollable(el)&&/auto|scroll/.test(getComputedStyle(el).overflowY));
    if(containers.length>1) throw Error('Focus the area you want to scroll');
    return containers[0] || root;
  }
  function flush() { if(observer.takeRecords().length) { cache=null; revision++; } }
  // Only same-tab ordinary links can be verified by observing the destination URL.
  function navigationURL(el) {
    if(!el?.matches('a[href]') || el.hasAttribute('download')) return null;
    const target=(el.getAttribute('target') || document.querySelector('base[target]')?.getAttribute('target') || '').toLowerCase();
    if(target && target!=='_self') return null;
    try { const url=new URL(el.href,location.href);return /^https?:$/.test(url.protocol) && url.href!==location.href ? url.href : null; } catch {return null;}
  }
  function signature(el) {
    const r=el.getBoundingClientRect();
    const relation=activationRelation(el);
    return JSON.stringify([el.tagName,el.getAttribute('role'),controlRole(el),el instanceof HTMLInputElement?el.type:null,labels(el),enabled(el),el.getAttribute('href'),el.getAttribute('target'),el.hasAttribute('download'),navigationURL(el),r.x,r.y,r.width,r.height,relation.kind,relation.key,relation.valid,identity(relation.target)]);
  }
  function observe(target) {
    flush();
    const context=targetContext(target),scope=context.scope;
    const all=controls().filter(el=>within(scope,el) && visible(el) && (typeof target!=='string' || (clickable(el) && matchesTarget(el,context.target))));
    const observationId=`${documentId}/${++observationSequence}`;
    observations.set(observationId,new Map(all.slice(0,48).map(el=>[identity(el),{signature:signature(el),scope:context.qualified?scope:null,query:context.qualified?target:null}])));
    while(observations.size>4) observations.delete(observations.keys().next().value);
    return {
      version:1,documentId,observationId,targetQuery:typeof target==='string'?target:null,
      capturedAt:Date.now(),revision,origin:location.origin,url:location.href,
      viewport:{width:innerWidth,height:innerHeight,scale:devicePixelRatio},
      focusedId:identity(active()),truncated:all.length>48,
      candidates:all.slice(0,48).map(el=>{
        const r=el.getBoundingClientRect();
        return {id:identity(el),role:controlRole(el),
          labels:labels(el).slice(0,3).map(s=>s.slice(0,100)),
          bounds:{x:r.x,y:r.y,width:r.width,height:r.height},
          enabled:enabled(el),editable:!!editable(el),clickable:clickable(el),navigationURL:navigationURL(el),
          selected:el.getAttribute('aria-selected'),expanded:el.getAttribute('aria-expanded')};
      })
    };
  }
  function targetFor(request) {
    switch(request.op) {
      case 'prepareSearch': return searchField();
      case 'type': return typingField(request);
      case 'fill': return chooseRequest(request,editable);
      case 'click': return chooseRequest(request,clickable);
      case 'select': return chooseRequest(request,el=>el instanceof HTMLSelectElement);
      case 'check': return chooseRequest(request,checkable);
      case 'scroll': return scrollTarget();
      default: return null;
    }
  }
  function state(el) {
    return {connected:!!el?.isConnected,focused:active()===el,
      value:el && editable(el) ? value(el) : el instanceof HTMLSelectElement ? el.value : null,
      checked:el ? checkedValue(el) : null,
      expanded:el?.getAttribute('aria-expanded'),selected:el?.getAttribute('aria-selected'),
      scrollTop:el?.scrollTop,scrollLeft:el?.scrollLeft,url:location.href};
  }
  // Keep field content out of ordinary diagnostic records.
  function evidence(s) {
    return {connected:s.connected,focused:s.focused,valueLength:s.value?.length??null,
      checked:s.checked,expanded:s.expanded,selected:s.selected,scrollTop:s.scrollTop,scrollLeft:s.scrollLeft};
  }
  // Bind outcome evidence to the selected control's explicit relationship, not
  // arbitrary page mutations. ID references resolve inside the same shadow root.
  function activationRelation(el) {
    const root=el.getRootNode(),details=detailsFor(el);
    if(details) return {kind:'details',key:identity(details),root,target:details,valid:true};
    const popover=el.popoverTargetElement,hasPopover=el.hasAttribute('popovertarget') || !!popover;
    const controls=el.getAttribute('aria-controls');
    if(!hasPopover && controls===null) return {kind:'none',key:'',root,target:null,valid:true};
    const id=(hasPopover?el.getAttribute('popovertarget'):controls)?.trim() || '';
    const kind=hasPopover?'popover':'controls';
    const key=JSON.stringify([id,hasPopover?el.popoverTargetAction:null,controls]);
    if(!id || id.length>256 || /\s/.test(id)) return {kind,key,root,target:null,valid:false};
    // Hex escapes also handle leading digits, punctuation and non-ASCII IDs.
    const selector='#'+Array.from(id,c=>'\\'+c.codePointAt(0).toString(16)+' ').join('');
    const matches=root.querySelectorAll(selector),target=matches.length===1?matches[0]:null;
    const valid=matches.length<=1 && (!hasPopover || (!target || (target===popover && target.hasAttribute('popover')))) &&
      (!hasPopover || controls===null || controls.trim()===id);
    return {kind,key,root,target,valid};
  }
  function activationState(el) {
    const relation=activationRelation(el),signals={};
    let valid=el.isConnected && relation.valid;
    for(const name of ['expanded','selected','pressed']) {
      const raw=el.getAttribute('aria-'+name);
      if(raw!==null && !['true','false',...(name==='pressed'?['mixed']:[])].includes(raw)) valid=false;
      signals[name]=raw;
    }
    if(nativeCheck(el) || el.matches('[role=checkbox],[role=switch],[role=radio],[role=menuitemcheckbox],[role=menuitemradio],[role=option]')) {
      const value=checkedValue(el);
      // Options may expose selected instead. Other checked widgets require a
      // valid native/ARIA checked state; arbitrary attributes are not proof.
      if(value!==null) {if(!validChecked(el,value)) valid=false;signals.checked=value;}
      else if(!el.matches('[role=option]')) valid=false;
    }
    const target=relation.target;
    const shown=relation.kind==='none'?null:relation.kind==='details'?!!target?.open:
      relation.kind==='popover'?!!target?.matches(':popover-open'):!!target && painted(target);
    return {relation,signals,shown,valid,role:el.getAttribute('role'),tag:el.tagName};
  }
  function activationChange(before,after) {
    const a=before.relation,b=after.relation;
    if(!before.valid || !after.valid || before.role!==after.role || before.tag!==after.tag ||
       a.root!==b.root || a.kind!==b.kind || a.key!==b.key ||
       (a.target && b.target && a.target!==b.target) || (a.target && !b.target && a.target.isConnected)) return null;
    // An explicit expanded state must agree with its associated surface.
    if(b.kind!=='none' && after.signals.expanded!==null && (after.signals.expanded==='true')!==after.shown) return null;
    const signals=Object.keys(before.signals).filter(key=>before.signals[key]!==null && after.signals[key]!==null && before.signals[key]!==after.signals[key]);
    const surface=b.kind!=='none' && before.shown!==after.shown;
    if(!signals.length && !surface) return null;
    if(b.kind!=='none' && after.shown && (!b.target || !visible(b.target))) return null;
    return {key:JSON.stringify([after.signals,after.shown,identity(b.target)]),signals,surface:surface?b.kind:null};
  }
  async function verifyActivation(el,before,request,binding) {
    const started=performance.now();let matchedAt=null,proof=null;
    const measurable=before.relation.kind!=='none' || Object.values(before.signals).some(value=>value!==null);
    if(!measurable || !before.valid) return null;
    while(performance.now()-started<500) {
      checkContext({...request,expectedURL:location.href});
      recheckScopedTarget(request,el,binding);
      const candidate=activationChange(before,activationState(el)),now=performance.now();
      // Once observed, reversal/replacement/contradiction ends verification.
      // This function only reads state; it never repeats the click.
      if(proof && (!candidate || candidate.key!==proof.key)) return null;
      if(candidate) {
        if(matchedAt===null) {matchedAt=now;proof=candidate;}
        if(now-matchedAt>=120) return {signals:proof.signals,surface:proof.surface,stableMs:now-matchedAt};
      }
      await new Promise(resolve=>setTimeout(resolve,20));
    }
    return null;
  }
  async function runVerified(request) {
    const started=performance.now(), commandId=request.commandId || crypto.randomUUID();
    let before,el;
    try {
      checkContext(request);
      if(request.op==='capabilities') return {...run(request),verifiedDispatch:true,existingTextOperations:true,message:'Verified dispatcher'};
      if(request.op==='observe') return run(request);
      if(request.op==='observeXSearch') return {ok:true,xSearch:xSearchEvidence(request.value),message:'Search state observed'};
      if(['copyText','changeCase'].includes(request.op)) return runExistingText(request,commandId,started);
      if(request.op==='armSearch') {
        const ticket=pendingSearch;pendingSearch=null;
        if(!ticket || request.token!==ticket.token || request.documentId!==documentId || Date.now()>ticket.expiresAt || active()!==ticket.el || !within(interactionScope(),ticket.el) || !visible(ticket.el) || !enabled(ticket.el) || ticket.el.readOnly || value(ticket.el)!==ticket.value || signature(ticket.el)!==ticket.signature) throw Error('Search target changed or preparation expired; no key sent');
        searchSubmissionAllowed(ticket.el);
        return {ok:true,armedToken:ticket.token,outcome:'verified',message:'Search field rechecked'};
      }
      pendingSearch=null;
      el=targetFor(request);before=state(el);
      const binding=scopeBinding(request);
      const observation=observe();
      const expectedNavigationURL=request.op==='click'?navigationURL(el):null;
      const activation=request.op==='click' && !editable(el)?activationState(el):null;
      const result=run(request);
      if(!result.ok) return {...result,commandId,outcome:'failed'};
      // A full navigation destroys this document and its pending async verifier.
      // Acknowledge the single dispatch promptly; native code observes the exact URL.
      if(expectedNavigationURL) return {ok:true,commandId,outcome:location.href===expectedNavigationURL?'verified':'unverified',message:'Navigation requested; destination not yet verified',expectedNavigationURL,documentId,targetId:identity(el),totalMs:performance.now()-started,domMs:result.domMs};
      if(activation) {
        const transition=await verifyActivation(el,activation,request,binding);
        return {ok:true,commandId,outcome:transition?'verified':'unverified',message:transition?'Control transition verified':'Click delivered; result not verified',
          transition,observationId:observation.observationId,documentId,targetId:identity(el),
          evidence:{before:evidence(before),after:evidence(state(el))},totalMs:performance.now()-started,domMs:result.domMs};
      }
      const expected=state(el);
      // No sleeps on dispatch. Observe rendering afterwards; never replay an action.
      const verifyStart=performance.now();
      let after=expected;
      while(performance.now()-verifyStart<180) {
        await new Promise(resolve=>setTimeout(resolve,30));
        checkContext({...request,expectedURL:location.href}); after=state(el);
        recheckScopedTarget(request,el,binding);
        if(['type','fill','prepareSearch','select','check'].includes(request.op)) {
          if(!after.connected || !within(interactionScope(),el) || (['type','fill','prepareSearch','select'].includes(request.op) && after.value!==expected.value) || (request.op==='check' && after.checked!==expected.checked)) {
            return {ok:false,commandId,outcome:'failed',error:'The page reverted or replaced the control; action not repeated',evidence:{before:evidence(before),after:evidence(after)}};
          }
        }
      }
      let verified=false, reason='No conclusive result observed; action not repeated';
      if(['type','fill','prepareSearch'].includes(request.op)) { verified=after.focused;reason=verified?'Text remained in the intended field':'Field lost focus before verification'; }
      else if(request.op==='select') {verified=true;reason='Selection remained set';}
      else if(request.op==='check') {verified=true;reason='Checkable control state remained set';}
      else if(request.op==='scroll') {
        verified=after.scrollTop!==before.scrollTop || after.scrollLeft!==before.scrollLeft;
        reason=verified?'Scroll movement verified':'No scroll movement — the area may be at its boundary';
      } else if(request.op==='click') {
        verified=after.connected && after.focused;
        reason=verified?'Field focus verified':'Click delivered; result not verified';
      } else { reason='Action delivered; result not verified'; }
      let nativeSearch;
      if(request.op==='prepareSearch') {
        if(!verified || location.href!==request.expectedURL) throw Error('Search field changed before preparation completed');
        pendingSearch={token:crypto.randomUUID(),el,value:value(el),signature:signature(el),expiresAt:Date.now()+1500};
        nativeSearch={token:pendingSearch.token,documentId,targetId:identity(el)};
        const token=pendingSearch.token;setTimeout(()=>{if(pendingSearch?.token===token)pendingSearch=null;},1500);
      }
      return {ok:true,commandId,nativeSearch,outcome:verified?'verified':'unverified',message:reason,
        observationId:observation.observationId,documentId,targetId:identity(el),
        evidence:{before:evidence(before),after:evidence(after)},totalMs:performance.now()-started,domMs:result.domMs};
    } catch(error) {
      return {ok:false,commandId,outcome:before?'unverified':'failed',error:error.message};
    }
  }
  globalThis.LocalVoiceDOM=Object.freeze({version:16,run,runVerified,observe,dispose:()=>observer.disconnect()});
})();
