import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('notice_pack',Path(__file__).parents[1]/'tools/pack_runtime_notices.py')
pack=importlib.util.module_from_spec(spec);spec.loader.exec_module(pack)


class NoticePackTests(unittest.TestCase):
    def fixture(self,root):
        site=root/'env/lib/python3.12/site-packages';site.mkdir(parents=True)
        data=b'Copyright Example\nPermission notice\n';(site/'LICENSE').write_bytes(data)
        record=dict(path='LICENSE',bytes=len(data),sha256=pack.digest(data))
        package=dict(name='sample',version='1.0',installedNoticeFiles=[record],licenseExpression='MIT',licenseClassifiers=[])
        return dict(environments={'parser':dict(packages=[package])}),dict(parserPython=str(root/'env/bin/python')),dict(records=[]),data

    def test_exact_bytes_manifest_and_deterministic_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);inventory,runtime,upstream,data=self.fixture(root)
            files,manifest=pack.collect(inventory,runtime,upstream,root)
            name=manifest['packages'][0]['noticeFiles'][0];self.assertEqual(files[name],data)
            a=root/'a.tar.gz';b=root/'b.tar.gz';pack.write(files,a);pack.write(files,b)
            self.assertEqual(a.read_bytes(),b.read_bytes())
            with tarfile.open(a) as archive:
                self.assertEqual(archive.extractfile('local-voice-runtime-notices/'+name).read(),data)
                recorded=json.load(archive.extractfile('local-voice-runtime-notices/MANIFEST.json'))
                self.assertEqual(recorded['files'][name]['sha256'],pack.digest(data))
            before=a.read_bytes()
            with self.assertRaises(FileExistsError):pack.write(files,a)
            self.assertEqual(a.read_bytes(),before)

    def test_changed_notice_or_uncovered_package_rejects(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);inventory,runtime,upstream,_=self.fixture(root)
            package=inventory['environments']['parser']['packages'][0]
            package['installedNoticeFiles'][0]['sha256']='bad'
            with self.assertRaises(ValueError):pack.collect(inventory,runtime,upstream,root)
            package['installedNoticeFiles']=[]
            with self.assertRaises(ValueError):pack.collect(inventory,runtime,upstream,root)

    def test_unsafe_relative_paths_reject(self):
        for name in ['../LICENSE','/LICENSE','a/../LICENSE','a//LICENSE','a\\LICENSE','']:
            with self.subTest(name=name),self.assertRaises(ValueError):pack.relative(name)

    def test_supplemental_notice_covers_missing_wheel_notice(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);inventory,runtime,upstream,_=self.fixture(root)
            inventory['environments']['parser']['packages'][0]['installedNoticeFiles']=[]
            data=b'Upstream license\n';(root/'LICENSE').write_bytes(data)
            upstream['records']=[dict(package='sample',version='1.0',files=[dict(path='LICENSE',bytes=len(data),sha256=pack.digest(data),url='https://example.org/LICENSE')])]
            files,manifest=pack.collect(inventory,runtime,upstream,root)
            self.assertEqual(files['upstream/LICENSE'],data)
            self.assertEqual(manifest['packages'][0]['upstreamURLs'],['https://example.org/LICENSE'])


if __name__=='__main__':unittest.main()
