"""Resident GoClick worker. Private stdin/stdout only; predictions never execute input.

One ephemeral frame/feature cache. No image files, HTTP listener, telemetry or downloads.
"""
import base64
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import re
import select
import sys
import time

MAX_LINE = 8 * 1024 * 1024
FRAME_TTL = 15.0


def parse_point(text):
    matches = re.findall(r'<loc_(\d+)>\s*,?\s*<loc_(\d+)>', text)
    if len(matches) != 1:
        raise ValueError('Vision did not return one target')
    x, y = map(int, matches[0])
    if not (0 <= x <= 1000 and 0 <= y <= 1000):
        raise ValueError('Vision coordinates are out of bounds')
    return [x / 1000, y / 1000]


class Worker:
    def __init__(self, model_path):
        os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
        os.environ['HF_HUB_OFFLINE'] = '1'
        os.environ['TRANSFORMERS_OFFLINE'] = '1'
        if not Path(model_path).is_dir():
            raise ValueError('Local GoClick weights are missing; run the offline model setup')
        import mlx.core as mx
        from mlx.utils import tree_map_with_path
        from mlx_vlm import load
        self.mx = mx
        self.model, self.processor = load(model_path, trust_remote_code=False)
        predicate = getattr(self.model, 'cast_predicate', None) or (lambda path: True)
        self.model.update(tree_map_with_path(lambda path, p: p.astype(mx.float16)
                          if mx.issubdtype(p.dtype, mx.floating) and predicate(path) else p,
                          self.model.parameters()))
        mx.eval(self.model.parameters())
        self.frame = None
        # Compile the same encoder/decoder path without any screen capture.
        from PIL import Image
        blank = Image.new('RGB', (1024, 640), 'white')
        self._prepare('warmup', blank)
        self._predict('warmup', 'button')
        self.frame = None
        mx.clear_cache()

    def _prepare(self, frame_id, image):
        image.thumbnail((1024, 1024))
        start = time.perf_counter()
        pixels = self.processor.image_processor(images=image, return_tensors='np')['pixel_values']
        features = self.model._encode_image(self.mx.array(pixels))
        self.mx.eval(features)
        self.mx.synchronize()
        self.frame = (frame_id, time.monotonic(), image, features)
        return {'ok': True, 'frameId': frame_id, 'prepareMs': (time.perf_counter()-start)*1000}

    def _predict(self, frame_id, target):
        if not self.frame or self.frame[0] != frame_id or time.monotonic()-self.frame[1] > FRAME_TTL:
            self.frame = None
            raise ValueError('Visual frame expired; capture again')
        from mlx_vlm.generate import stream_generate
        _, _, image, features = self.frame
        start = time.perf_counter()
        prompt = f'Where is the {target} element? (Output the center coordinates of the target)'
        output = ''.join(chunk.text for chunk in stream_generate(
            self.model, self.processor, prompt, image=[image], max_tokens=32,
            temperature=0.0, enable_thinking=False, verbose=False, cached_image_features=features))
        self.mx.synchronize()
        return {'ok': True, 'frameId': frame_id, 'point': parse_point(output),
                'predictMs': (time.perf_counter()-start)*1000}

    def request(self, request):
        op = request.get('op')
        if op == 'warm':
            return {'ok': True}
        if op == 'clear':
            self.frame = None
            self.mx.clear_cache()
            return {'ok': True}
        frame_id = request.get('frameId')
        if not isinstance(frame_id, str) or not 1 <= len(frame_id) <= 128:
            raise ValueError('Invalid frame identity')
        if op == 'prepare':
            self.frame = None  # A bad replacement must not leave an old frame usable.
            encoded = request.get('image', '')
            if not isinstance(encoded, str) or len(encoded) > MAX_LINE-1024:
                raise ValueError('Image exceeds the bounded request size')
            raw = base64.b64decode(encoded, validate=True)
            if hashlib.sha256(raw).hexdigest() != request.get('imageSHA256'):
                raise ValueError('Image identity mismatch')
            from PIL import Image
            image = Image.open(io.BytesIO(raw))
            if image.width > 1024 or image.height > 1024 or image.width < 1 or image.height < 1:
                raise ValueError('Expected a bounded 1024-pixel image')
            image.load()
            return self._prepare(frame_id, image.convert('RGB'))
        if op == 'predict':
            target = request.get('target')
            if not isinstance(target, str) or not 1 <= len(target) <= 300 or any(ord(c) < 32 for c in target):
                raise ValueError('Invalid target description')
            return self._predict(frame_id, target)
        raise ValueError('Unsupported vision request')


def main():
    protocol = sys.stdout
    parent = os.getppid()
    with contextlib.redirect_stdout(sys.stderr):
        worker = Worker(sys.argv[1])
    while os.getppid() == parent:
        if worker.frame and time.monotonic()-worker.frame[1] > FRAME_TTL:
            worker.frame = None
            worker.mx.clear_cache()
        if not select.select([sys.stdin.buffer], [], [], 1)[0]:
            continue
        line = sys.stdin.buffer.readline(MAX_LINE + 1)
        if not line:
            return
        if len(line) > MAX_LINE or not line.endswith(b'\n'):
            return  # Never interpret a truncated or oversized message.
        request_id = None
        try:
            request = json.loads(line)
            request_id = request['id']
            if not isinstance(request_id, str) or len(request_id) > 128:
                raise ValueError('Invalid request ID')
            with contextlib.redirect_stdout(sys.stderr):
                reply = worker.request(request)
        except Exception as error:
            # Error category only: never echo image bytes, model output or command text.
            reply = {'ok': False, 'error': str(error) if isinstance(error, ValueError) else type(error).__name__}
        protocol.write(json.dumps(dict(reply, id=request_id)) + '\n')
        protocol.flush()


if __name__ == '__main__':
    main()
