import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import export_source as module


class SourceExportTests(unittest.TestCase):
    def fixture(self,root):
        source=root/'voice/app.swift';source.parent.mkdir(parents=True);source.write_text('print("hello")\n')
        (root/'.env').write_text('private fixture, never export')
        (root/'voice/trace.json').write_text('personal trace fixture')
        (root/'voice/build.sh').write_text('#!/bin/sh\nexit 0\n')
        return {'version':1,'files':[{'source':'voice/app.swift'},{'source':'voice/build.sh','executable':True}]}

    def test_explicit_selection_and_reproducible_hashes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);listing=self.fixture(root)
            files=module.collect(root,listing)
            first=root/'one.tar.gz';second=root/'two.tar.gz'
            a=module.write_archive(files,first);b=module.write_archive(files,second)
            self.assertEqual(a,b);self.assertEqual(first.read_bytes(),second.read_bytes())
            with tarfile.open(first) as archive:
                names=set(archive.getnames())
                self.assertEqual(names,{module.PREFIX+'/'+n for n in ['voice/app.swift','voice/build.sh',module.MANIFEST]})
                manifest=json.load(archive.extractfile(module.PREFIX+'/'+module.MANIFEST))
                for name,(data,mode) in files.items():
                    entry=archive.getmember(module.PREFIX+'/'+name)
                    self.assertEqual(entry.mode,mode);self.assertEqual(entry.mtime,0)
                    self.assertTrue(entry.isfile());self.assertEqual(entry.uid,0)
                    self.assertEqual(manifest['files'][name]['sha256'],hashlib.sha256(data).hexdigest())

    def test_private_and_generated_paths_reject_even_if_listed(self):
        with tempfile.TemporaryDirectory() as temp:
            for name in ['.env','voice/.env.local','.cache/frame.json','runs/request.json',
                         'voice/research/grounded/live/result.json','voice/browser/host-config.json',
                         'voice/parser/artifacts/parser.pt','image.png','signing.pem']:
                with self.subTest(name=name),self.assertRaises(ValueError):
                    module.collect(Path(temp),{'version':1,'files':[{'source':name}]})

    def test_traversal_absolute_and_noncanonical_paths_reject(self):
        for name in ['../file','/tmp/file','a/../../file','a//file','a/./file','a\\file']:
            with self.subTest(name=name),self.assertRaises(ValueError):module.safe_name(name)

    def test_symlinks_and_symlinked_ancestors_reject(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);listing=self.fixture(root)
            real=root/'voice/app.swift';link=root/'alias.swift';link.symlink_to(real)
            with self.assertRaisesRegex(ValueError,'Symlink'):module.collect(root,{'version':1,'files':[{'source':'alias.swift'}]})
            (root/'linked').symlink_to(root/'voice',target_is_directory=True)
            with self.assertRaisesRegex(ValueError,'Symlink'):module.collect(root,{'version':1,'files':[{'source':'linked/app.swift'}]})

    def test_secret_rejection_does_not_echo_secret(self):
        credential='apikey_'+'a'*32+'_'+'b'*64
        private_key='-----BEGIN '+'PRIVATE KEY-----'
        home_path='/Users/'+'private-person/project/file'
        for content in [credential,private_key,home_path]:
            with self.subTest(kind=content[:6]),self.assertRaises(ValueError) as raised:
                module.inspect_text(('header\n'+content).encode(),'voice/file.py')
            self.assertNotIn(content,str(raised.exception));self.assertIn('voice/file.py:2',str(raised.exception))

    def test_binary_and_oversized_sources_reject(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);listing=self.fixture(root);path=root/'voice/app.swift'
            path.write_bytes(b'\x00binary')
            with self.assertRaisesRegex(ValueError,'Binary'):module.collect(root,listing)
            path.write_bytes(b'\xff')
            with self.assertRaisesRegex(ValueError,'Non-text'):module.collect(root,listing)
            path.write_text('x'*20)
            with patch.object(module,'MAX_FILE',10),self.assertRaisesRegex(ValueError,'size limit'):module.collect(root,listing)

    def test_duplicate_case_insensitive_and_reserved_destinations_reject(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);self.fixture(root)
            for destinations in [['a.swift','A.swift'],[module.MANIFEST]]:
                listing={'version':1,'files':[{'source':'voice/app.swift','destination':name} for name in destinations]}
                with self.assertRaises(ValueError):module.collect(root,listing)

    def test_missing_source_does_not_create_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);listing=root/'list.json';listing.write_text(json.dumps({'version':1,'files':[{'source':'missing.swift'}]}))
            output=root/'source.tar.gz'
            with self.assertRaisesRegex(ValueError,'Missing'):module.export(root,listing,output)
            self.assertFalse(output.exists())

    def test_existing_output_is_preserved_and_failed_publication_cleans_temp(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);files=module.collect(root,self.fixture(root));output=root/'source.tar.gz'
            output.write_bytes(b'previous')
            with self.assertRaises(FileExistsError):module.write_archive(files,output)
            self.assertEqual(output.read_bytes(),b'previous');output.unlink()
            with patch('export_source.os.link',side_effect=OSError('fixture failure')),self.assertRaises(OSError):
                module.write_archive(files,output)
            self.assertFalse(list(root.glob('.source-export-*')));self.assertFalse(output.exists())

    def test_symlinked_file_list_rejects(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);listing=self.fixture(root);actual=root/'actual.json';actual.write_text(json.dumps(listing))
            alias=root/'list.json';alias.symlink_to(actual)
            with self.assertRaisesRegex(ValueError,'Symlink'):module.export(root,alias)


if __name__=='__main__':unittest.main()
