"""Experimental local cross-encoder. Scores observed controls; never executes them."""
import os
os.environ['HF_HUB_OFFLINE']='1'
os.environ['TRANSFORMERS_OFFLINE']='1'
os.environ['TOKENIZERS_PARALLELISM']='false'
import math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
MODEL_ROOT=Path(os.environ['LOCALVOICE_MODEL_DIR']) if os.environ.get('LOCALVOICE_MODEL_DIR') else None
BASE=MODEL_ROOT/'base' if MODEL_ROOT else ROOT/'voice/parser/artifacts/base'
CHECKPOINT=MODEL_ROOT/'ranker.pt' if MODEL_ROOT else ROOT/'.cache/grounded-ranker/candidate.pt'
ROLES={'link','a','button','textbox','input','searchbox','textarea'}

def bind_selection(observation, target_id, confidence, margin, threshold=.98, min_margin=.20):
    """Bind once to a snapshot; executor must revalidate it before input.
    Returned command must never be reused after an action or document mutation.
    """
    if not all(math.isfinite(v) for v in (confidence,margin)) or confidence<threshold or margin<min_margin:
        return None
    if not observation.get('documentId') or not observation.get('observationId'):
        return None
    matches=[c for c in observation.get('candidates',[]) if c.get('id')==target_id]
    if len(matches)!=1 or not matches[0].get('enabled') or matches[0].get('role') not in ROLES:
        return None
    return dict(op='click',targetId=target_id,documentId=observation['documentId'],observationId=observation['observationId'])

def label(c):return c.get('label') or ' | '.join(c.get('labels',[]))
def description(c):return c['role']+' : '+label(c)

def build_model(pretrained=False):
    import torch
    from torch import nn
    from transformers import BertConfig,BertModel
    class Ranker(nn.Module):
        def __init__(self):
            super().__init__()
            self.encoder=BertModel.from_pretrained(str(BASE)) if pretrained else BertModel(BertConfig.from_pretrained(str(BASE)))
            self.score=nn.Linear(128,1)
        def forward(self,**batch):
            return self.score(self.encoder(**batch).last_hidden_state[:,0]).squeeze(-1)
    return Ranker()

class Predictor:
    def __init__(self, checkpoint=CHECKPOINT):
        import torch
        from transformers import BertTokenizerFast
        torch.set_num_threads(2)
        self.tok=BertTokenizerFast(vocab_file=str(BASE/'vocab.txt'),do_lower_case=True)
        self.model=build_model()
        self.model.load_state_dict(torch.load(checkpoint,map_location='cpu',weights_only=True))
        self.model.eval()
    def predict(self,text,observation):
        import torch
        # Whole requests, not a truncated prefix that might omit a negation/second action.
        if not isinstance(text,str) or not text.strip() or len(self.tok.encode(text))>96:
            return dict(command=None,reason='request_too_long_or_empty',scores=[])
        candidates=observation.get('candidates',[])
        if len(candidates)>48:
            return dict(command=None,reason='too_many_candidates',scores=[])
        ids=[c.get('id') for c in candidates]
        if any(not isinstance(i,str) or not i for i in ids) or len(set(ids))!=len(ids):
            return dict(command=None,reason='invalid_candidate_ids',scores=[])
        candidates=[c for c in candidates if c.get('enabled') and c.get('role') in ROLES and label(c)]
        if not candidates:return dict(command=None,reason='no_candidates',scores=[])
        batch=self.tok([text]*len(candidates),[description(c) for c in candidates],padding=True,truncation='only_second',max_length=160,return_tensors='pt')
        with torch.inference_mode(): probs=self.model(**batch).sigmoid().tolist()
        scores=sorted([dict(id=c['id'],score=p) for c,p in zip(candidates,probs)],key=lambda x:x['score'],reverse=True)
        best=scores[0];margin=best['score']-(scores[1]['score'] if len(scores)>1 else 0)
        command=bind_selection(observation,best['id'],best['score'],margin)
        return dict(command=command,reason='bound' if command else 'uncertain',scores=scores,margin=margin)
