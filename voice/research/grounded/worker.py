"""Experimental JSON-lines worker. Prints proposals only; no execution capability."""
import argparse,json,sys,time
from ranker import Predictor

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--grounded-v2',action='store_true',help='Use operation-gated pipeline; requires production observation capabilities')
    args=parser.parse_args()
    if args.grounded_v2:
        from pipeline import GroundedPipeline
        predictor=GroundedPipeline()
    else:
        predictor=Predictor()
    for line in sys.stdin:
        try:
            request=json.loads(line)
            if not isinstance(request,dict):
                raise ValueError('Expected request object')
            started=time.perf_counter()
            if request.get('kind')=='preflight' and args.grounded_v2:
                texts=request.get('texts')
                if not isinstance(texts,list) or not 1<=len(texts)<=3 or any(not isinstance(t,str) or not t.strip() for t in texts):
                    raise ValueError('Expected one to three complete operations')
                from pipeline import qualified_request
                result=dict(operations=[predictor.intent.predict(qualified_request(t)[1]) for t in texts])
            else:
                if not isinstance(request.get('observation'),dict):
                    raise ValueError('Expected observation object')
                result=predictor.predict(request.get('text'),request['observation'])
            result['milliseconds']=(time.perf_counter()-started)*1000
            # ID is opaque correlation metadata, never model input.
            print(json.dumps(dict(id=request.get('id'),**result)),flush=True)
        except (ValueError,TypeError,KeyError,AttributeError) as error:
            print(json.dumps(dict(command=None,error=type(error).__name__)),flush=True)
if __name__=='__main__':main()
