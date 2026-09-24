import os
os.environ.setdefault('TOKENIZERS_PARALLELISM','false')
import torch
from torch import nn
from transformers import BertConfig, BertModel, BertTokenizerFast
from pathlib import Path
ROOT=Path(__file__).resolve().parent
MODEL_ROOT=Path(os.environ.get('LOCALVOICE_MODEL_DIR',str(ROOT/'artifacts')))
BASE=MODEL_ROOT/'base'
ACTIONS=['abstain','openApp','createNote','titleNote','searchWeb','openURL','takePhoto']
torch.set_num_threads(2)
class ParserModel(nn.Module):
    def __init__(self, pretrained=False):
        super().__init__()
        self.encoder=BertModel.from_pretrained(str(BASE)) if pretrained else BertModel(BertConfig.from_pretrained(str(BASE)))
        self.intent=nn.Linear(128,len(ACTIONS))
        self.span=nn.Linear(128,2)
    def forward(self, **x):
        hidden=self.encoder(**x).last_hidden_state
        return self.intent(hidden[:,0]), self.span(hidden).unbind(-1)
def tokenizer():
    return BertTokenizerFast(vocab_file=str(BASE/'vocab.txt'),do_lower_case=True)
def encode(tok, rows):
    batch=tok([r['text'] for r in rows],padding=True,truncation=True,max_length=96,return_offsets_mapping=True,return_tensors='pt')
    offsets=batch.pop('offset_mapping'); starts=[]; ends=[]
    for row, spans in zip(rows,offsets.tolist()):
        indices=[i for i,(a,b) in enumerate(spans) if b>a and a>=row['start'] and b<=row['end']] if row['value'] else []
        starts.append(indices[0] if indices else 0); ends.append(indices[-1] if indices else 0)
    return batch,torch.tensor([ACTIONS.index(r['action']) for r in rows]),torch.tensor(starts),torch.tensor(ends)
class Predictor:
    def __init__(self):
        self.tok=tokenizer(); self.model=ParserModel()
        self.model.load_state_dict(torch.load(MODEL_ROOT/'parser.pt',map_location='cpu',weights_only=True)); self.model.eval()
    @torch.inference_mode()
    def predict(self,text):
        batch=self.tok(text,return_offsets_mapping=True,return_tensors='pt',truncation=True,max_length=96)
        offsets=batch.pop('offset_mapping')[0].tolist()
        intent,(s,e)=self.model(**batch)
        p=intent.softmax(-1)[0]; idx=int(p.argmax()); start=int(s[0].argmax()); end=int(e[0].argmax())
        value=text[offsets[start][0]:offsets[end][1]] if 0<start<=end<len(offsets)-1 else ''
        return dict(action=ACTIONS[idx],value=value,confidence=round(float(p[idx]),4),spanConfidence=round(min(float(s.softmax(-1)[0,start]),float(e.softmax(-1)[0,end])),4))
