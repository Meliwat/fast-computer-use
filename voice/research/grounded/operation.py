"""Separate tiny operation classifier; trained weights never replace production parser."""
import json,random,time,hashlib
from pathlib import Path
from ranker import BASE,ROOT,MODEL_ROOT
import torch
from torch import nn
from transformers import BertConfig,BertModel,BertTokenizerFast
HERE=Path(__file__).resolve().parent
CHECKPOINT=MODEL_ROOT/'operation.pt' if MODEL_ROOT else ROOT/'.cache/grounded-operation/candidate.pt'
OPERATIONS=['abstain','activate','focus']
torch.set_num_threads(2)
class Model(nn.Module):
    def __init__(self,pretrained=False):
        super().__init__()
        self.encoder=BertModel.from_pretrained(str(BASE)) if pretrained else BertModel(BertConfig.from_pretrained(str(BASE)))
        self.operation=nn.Linear(128,len(OPERATIONS))
    def forward(self,**batch):return self.operation(self.encoder(**batch).last_hidden_state[:,0])
class OperationPredictor:
    def __init__(self):
        self.tok=BertTokenizerFast(vocab_file=str(BASE/'vocab.txt'),do_lower_case=True)
        self.model=Model();self.model.load_state_dict(torch.load(CHECKPOINT,map_location='cpu',weights_only=True));self.model.eval()
    @torch.inference_mode()
    def predict(self,text):
        if not isinstance(text,str) or not text.strip():return dict(operation='abstain',confidence=1.)
        batch=self.tok(text,return_tensors='pt')
        if batch['input_ids'].shape[1]>96:return dict(operation='abstain',confidence=1.)
        probs=self.model(**batch)[0].softmax(-1);idx=int(probs.argmax())
        return dict(operation=OPERATIONS[idx],confidence=float(probs[idx]))

def data():
    names=['Settings','Home','Notifications','Account','Help','Downloads','Documentation','Profile','Messages','Inbox','News','Community','Events','Jobs','Search','About','History','Tools','Comments','Library','Menu','Languages','Next','Back','Details','Preferences','Support','Cancel','Close','Reading Lists','Favorites','Submit','Continue','Categories','Security','Archive','Calendar','More','Overview','Reports']
    fields=['Search','Name','Email','Title','Message','Comment','Address','Phone','Filter','Query','Search books','User name']
    positives=['open {x}','click {x}','press {x}','tap {x}','show {x}','show me {x}','take me to {x}','go to {x}','bring up {x}','activate {x}','select {x}','let me see {x}','I want to see {x}','I want {x}','can you open {x}','could you show me {x}','expand {x}','minimize {x}','dismiss {x}','open the {x} menu','click the {x} button','open the {x} link']
    negatives=['delete {x}','erase {x}','remove {x}','buy {x}','purchase {x}','pay for {x}','send {x}','post {x}','publish {x}','install {x}','uninstall {x}',"don't click {x}",'do not open {x}','never press {x}','stop opening {x}','explain {x}','what is {x}?','what does {x} do?','where is {x}?','why is {x} here?','I clicked {x}','I already opened {x}','the instructions say click {x}','someone told me to open {x}','I was viewing {x}','open {x} and click Home','open {x} then type hello','click {x} after sending the message','maybe open {x} later','open {x} unless I cancel','search for {x}','find {x}','type {x}','write {x}','fill Name with {x}','scroll to {x}','select all {x}','summarize {x}']
    focusing=['focus {x}','focus the {x} field','click the {x} field','select the {x} input','activate the {x} text box','put the cursor in {x}','place the cursor in {x}','get the {x} field ready','let me type into {x}','prepare the {x} field for typing','move focus to {x}']
    train=[];valid=[];rng=random.Random(116)
    # Validation holds out target strings and request templates within this authored grammar.
    for i,name in enumerate(names):
        dest=valid if i%9==8 else train
        for operation,templates in [('activate',positives),('abstain',negatives)]:
            for t in templates:
                text=t.format(x=name);dest.append((text,operation))
                if dest is train:dest.append((rng.choice(['please ','okay ','now '])+text,operation))
    for i,name in enumerate(fields):
        dest=valid if i in (3,8) else train
        for t in focusing:
            text=t.format(x=name);dest.extend([(text,'focus'),('please '+text,'focus')])
        for t in ['type hello in {x}','clear {x}','fill {x} with blue','do not focus {x}','focus {x} and type hello','what is the {x} field?']:
            dest.append((t.format(x=name),'abstain'))
    for text in ['hello','thanks','do that','click it','open it','do whatever','yes','no','search this site','scroll down','new tab','close Chrome','launch Notes','make a note','the page says click here']:
        train.append((text,'abstain'))
    valid.extend((t.format(x='Privacy'),'activate') for t in ['navigate to {x}','bring me to {x}','I need to view {x}'])
    rng.shuffle(train);return train,valid

def train():
    torch.manual_seed(116);rows,valid=data();tok=BertTokenizerFast(vocab_file=str(BASE/'vocab.txt'),do_lower_case=True)
    def encode(rows):return tok([r[0] for r in rows],padding=True,return_tensors='pt'),torch.tensor([OPERATIONS.index(r[1]) for r in rows])
    x,y=encode(rows);vx,vy=encode(valid);model=Model(True);opt=torch.optim.AdamW(model.parameters(),lr=1e-4);lossfn=nn.CrossEntropyLoss();best=float('inf');history=[];began=time.perf_counter()
    CHECKPOINT.parent.mkdir(parents=True,exist_ok=True)
    for name,entries in [('train',rows),('validation',valid)]: (CHECKPOINT.parent/(name+'.json')).write_text(json.dumps(entries))
    for epoch in range(16):
        model.train()
        for ids in torch.randperm(len(rows)).split(64):
            opt.zero_grad();loss=lossfn(model(**{k:v[ids] for k,v in x.items()}),y[ids]);loss.backward();opt.step()
        model.eval()
        with torch.inference_mode():
            logits=model(**vx);vloss=float(lossfn(logits,vy));acc=float((logits.argmax(-1)==vy).float().mean())
        row=dict(epoch=epoch+1,validationLoss=vloss,validationAccuracy=acc,seconds=round(time.perf_counter()-began,2));history.append(row);print(json.dumps(row),flush=True)
        if vloss<best:best=vloss;torch.save(model.state_dict(),CHECKPOINT)
    metadata=dict(seed=116,parameters=sum(p.numel() for p in model.parameters()),trainExamples=len(rows),validationExamples=len(valid),history=history,checkpointSHA256=hashlib.sha256(CHECKPOINT.read_bytes()).hexdigest(),challengeSHA256=hashlib.sha256((HERE/'fresh-challenge.json').read_bytes()).hexdigest())
    (HERE/'operation-training.json').write_text(json.dumps(metadata,indent=2)+'\n')
if __name__=='__main__':train()
