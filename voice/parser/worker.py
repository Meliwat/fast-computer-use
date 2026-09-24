"""Resident, offline JSON-lines worker. No execution, network, or arbitrary code."""
import json,sys,time
from model import Predictor
p=Predictor()
p.predict('open Notes')
for line in sys.stdin:
    try:
        request=json.loads(line); text=request.get('text','')
        if not isinstance(text,str) or len(text)>1000: raise ValueError('Command is too long')
        start=time.perf_counter(); result=p.predict(text)
        result['milliseconds']=round((time.perf_counter()-start)*1000,2)
        # This checkpoint is experimental. Confidence is not a correctness guarantee.
        result['inferenceOnly']=True
        print(json.dumps(result),flush=True)
    except Exception as error:
        print(json.dumps(dict(error=str(error))),flush=True)
