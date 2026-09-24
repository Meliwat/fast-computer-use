"""Offline protocol checks; no model load, screen capture or execution."""
import base64
import hashlib
import io
import time
import unittest
from unittest.mock import Mock
from PIL import Image
from worker import Worker, parse_point


class WorkerContractTests(unittest.TestCase):
    def setUp(self):
        self.worker = Worker.__new__(Worker)
        self.worker.frame = None
        self.worker.mx = Mock()

    def image_request(self, size=(40, 20)):
        buf=io.BytesIO()
        Image.new('RGB',size,'white').save(buf,format='PNG')
        raw=buf.getvalue()
        return dict(op='prepare',frameId='frame-a',image=base64.b64encode(raw).decode(),imageSHA256=hashlib.sha256(raw).hexdigest())

    def test_location_contract(self):
        self.assertEqual(parse_point('<s>(<loc_250>,<loc_750>)'),[.25,.75])
        for output in ['NONE','[250,750]','<loc_1001>,<loc_25>','<loc_1>,<loc_2> <loc_3>,<loc_4>']:
            with self.assertRaises(ValueError):parse_point(output)

    def test_missing_wrong_and_expired_frames_cannot_predict(self):
        for frame in [None,('other',time.monotonic(),None,None),('a',time.monotonic()-16,None,None)]:
            self.worker.frame=frame
            with self.assertRaises(ValueError):self.worker.request(dict(op='predict',frameId='a',target='Settings'))
            self.assertIsNone(self.worker.frame)

    def test_prepare_integrity_and_replacement(self):
        self.worker._prepare=Mock(return_value={'ok':True})
        request=self.image_request()
        self.assertTrue(self.worker.request(request)['ok'])
        self.assertEqual(self.worker._prepare.call_count,1)
        self.worker.frame=('old',time.monotonic(),None,None)
        request['imageSHA256']='wrong'
        with self.assertRaises(ValueError):self.worker.request(request)
        self.assertIsNone(self.worker.frame)
        self.assertEqual(self.worker._prepare.call_count,1)

    def test_large_images_and_malformed_targets_reject(self):
        with self.assertRaises(ValueError):self.worker.request(self.image_request((1025,20)))
        for target in ['',None,'a'*301,'hello\nthere']:
            with self.assertRaises(ValueError):self.worker.request(dict(op='predict',frameId='a',target=target))
        with self.assertRaises(ValueError):self.worker.request(dict(op='execute',frameId='a'))

    def test_clear_drops_image_and_features(self):
        self.worker.frame=('a',time.monotonic(),object(),object())
        self.assertTrue(self.worker.request({'op':'clear'})['ok'])
        self.assertIsNone(self.worker.frame)
        self.worker.mx.clear_cache.assert_called_once()

if __name__=='__main__':unittest.main()
