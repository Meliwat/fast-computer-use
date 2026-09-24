"""Experimental operation gate + observed-name matching + semantic target ranking.
No executor, website rules, generated selectors or generated argument values.
"""
import re
from ranker import Predictor, label

def names(c):return c.get('labels') or ([c['label']] if c.get('label') else [])
def normal(s):return re.sub(r'\s+',' ',s.lower()).strip()

# Eligible activation widgets share the ranker's trained button/link semantics.
# Capability checks still happen first; this never turns plain text into input.
ACTIVATION_ROLE={'a':'link','link':'link','button':'button','input':'button',
                 'summary':'button','tab':'button','menuitem':'button',
                 'menuitemcheckbox':'button','menuitemradio':'button',
                 'checkbox':'button','switch':'button','radio':'button','option':'button'}

ROLE_WORDS={'radio button':'radio','menu item':'menuitem',
            'checkbox':'checkbox','switch':'switch','radio':'radio','option':'option',
            'tab':'tab','link':'link','button':'button','field':'textbox','box':'textbox','textbox':'textbox'}
ROLE_PATTERN='|'.join(re.escape(word).replace(r'\ ',r'\s+') for word in sorted(ROLE_WORDS,key=len,reverse=True))
ROLE_SUFFIX=re.compile(r'\s+('+ROLE_PATTERN+r')[.!?,;:]*$',re.I)
ROLE_PREFIX=re.compile(r'\b(?:the\s+)?('+ROLE_PATTERN+r')\s+(?:called|named|labelled|labeled)\s+',re.I)

def qualified_request(text,candidates=()):
    """Preserve literal observed labels; otherwise retain an explicit role hint.

    Only the role noun is normalized for the operation classifier. Negation,
    action verbs and the requested label remain in its input. Role matching uses
    the original hint, never the normalized button/link representation.
    """
    match=ROLE_PREFIX.search(text) or ROLE_SUFFIX.search(text)
    if match is None:return None,text,text
    # A label such as "Radio settings" or "Help link" remains a literal name.
    for candidate in candidates:
        for name in names(candidate):
            for label_match in re.finditer(r'(?<!\w)'+re.escape(name)+r'(?!\w)',text,re.I):
                if label_match.start()<=match.start(1) and label_match.end()>=match.end(1):
                    prefix=ACTION_PREFIX.match(normal(text))
                    tail=normal(text)[prefix.end() if prefix else 0:].strip().removeprefix('the ').rstrip('.!?')
                    if len(normal(name).split())>len(match.group(1).split()) or tail==normal(name):return None,text,text
    role=ROLE_WORDS[normal(match.group(1))]
    canonical='field' if role=='textbox' else 'link' if role=='link' else 'button'
    return role,text[:match.start(1)]+canonical+text[match.end(1):],text[:match.start(1)]+text[match.end(1):]

def matches_role(candidate,role):
    if role is None:return True
    actual=candidate.get('role')
    if role=='textbox':return candidate.get('editable') is True
    if candidate.get('editable') is True:return False
    if role=='link':return actual in ('a','link')
    if role=='button':return actual in ('button','input','summary')
    if role=='menuitem':return actual in ('menuitem','menuitemcheckbox','menuitemradio')
    return actual==role

# A leading action verb is not itself a named target: "Open Export PDF" must
# not take the exact-label shortcut to an unrelated button called "Open".
# A later occurrence ("open Open") still names the control normally.
ACTION_PREFIX=re.compile(
    r'^(?:(?:please|okay|ok|now)[,\s]+)*'
    r'(?:(?:can|could|would|will)\s+you\s+|(?:i\s+(?:would\s+like|want)|i\x27d\s+like)\s+to\s+)?'
    r'(?:please\s+)?(?:open|click|press|tap|show(?:\s+me)?|select|activate|expand|dismiss|'
    r'minimize|focus|view|bring|take|go|get|put|place|prepare)\b')

def mentioned_candidates(text,candidates):
    text=normal(text);prefix=ACTION_PREFIX.match(text);end=prefix.end() if prefix else 0
    spans=[]
    for index,candidate in enumerate(candidates):
        for name in {normal(v) for v in names(candidate) if normal(v)}:
            for match in re.finditer(r'(?<!\w)'+re.escape(name)+r'(?!\w)',text):
                if match.end()>end:spans.append((index,match.start(),match.end()))
    # Prefer a fully named longer label, while preserving duplicate equal names
    # and a separately mentioned short label: "Save and Save as" stays ambiguous.
    selected={i for i,start,end in spans if not any(a<=start and end<=b and (a<start or end<b) for _,a,b in spans)}
    return [c for i,c in enumerate(candidates) if i in selected]

class GroundedPipeline:
    def __init__(self,intent=None,ranker=None):
        if intent is None:
            from operation import OperationPredictor
            intent=OperationPredictor()
        self.intent=intent;self.ranker=ranker if ranker is not None else Predictor()
    def predict(self,text,observation):
        def reject(reason,operation=None):return dict(command=None,reason=reason,operation=operation,scores=[])
        if observation.get('version')!=1 or observation.get('truncated') is not False or not all(isinstance(observation.get(k),str) and observation[k] for k in ('documentId','observationId')):
            return reject('incomplete_observation')
        if not isinstance(text,str) or not text.strip():return reject('empty_request')
        candidates=observation.get('candidates',[])
        ids=[c.get('id') for c in candidates]
        if len(candidates)>48 or any(not isinstance(i,str) or not i for i in ids) or len(set(ids))!=len(ids):
            return reject('invalid_candidate_ids')
        role,operation_text,target_text=qualified_request(text,candidates)
        operation=self.intent.predict(operation_text)
        op=operation['operation']
        if op not in ('activate','focus') or not operation['confidence']>=.99:
            return reject('unsupported_or_uncertain_operation',operation)
        # Missing capability fields are not permission to act. Do not infer from a tag name.
        eligible=[c for c in candidates if c.get('enabled') is True and c.get('clickable') is True and c.get('editable') is (op=='focus') and matches_role(c,role)]
        if not eligible:return reject('no_eligible_controls',operation)
        mentioned=mentioned_candidates(target_text,candidates)
        if role and mentioned:
            mentioned=[c for c in mentioned if matches_role(c,role)]
            if not mentioned:return reject('named_control_role_mismatch',operation)
        if any(c.get('enabled') is not True for c in mentioned):return reject('named_control_disabled',operation)
        mentioned_ids={c['id'] for c in mentioned}
        exact=[c for c in eligible if c['id'] in mentioned_ids]
        if len(exact)>1:return reject('multiple_named_controls',operation)
        if len(exact)==1:
            selected=exact[0]
            result=dict(command=dict(op='click',targetId=selected['id'],documentId=observation['documentId'],observationId=observation['observationId']),reason='bound',scores=[],source='observed_label')
        else:
            # Normalize browser tags to the semantic roles used in ranker training.
            canonical=[dict(c,role='textbox' if c.get('editable') else ACTIVATION_ROLE.get(c['role'],c['role'])) for c in eligible]
            result=self.ranker.predict(operation_text,dict(observation,candidates=canonical));result['source']='semantic_ranker'
            if result['command']:selected=next(c for c in eligible if c['id']==result['command']['targetId'])
        result['operation']=operation
        if result['command']:
            selected_labels={normal(v) for v in names(selected)}
            cross_role=any(c.get('enabled') and c.get('editable') is True and any(normal(v) in selected_labels for v in names(c)) for c in candidates)
            if op=='activate' and cross_role and role is None and not re.search(r'\b(button|link|tab|menu)\b',text,re.I):
                return reject('ambiguous_control_role',operation)
        return result
