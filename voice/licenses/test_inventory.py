import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('license_inventory',Path(__file__).parents[1]/'tools/inventory_dependency_licenses.py')
inventory=importlib.util.module_from_spec(spec); spec.loader.exec_module(inventory)


class InventoryTests(unittest.TestCase):
    def fixture(self, root, version='1.0', notice='sample-1.0.dist-info/licenses/LICENSE.txt'):
        site=root/'environment/lib/python3.12/site-packages'; site.mkdir(parents=True)
        info=site/'sample-1.0.dist-info'; info.mkdir()
        (info/'METADATA').write_text(f'Metadata-Version: 2.4\nName: Sample\nVersion: {version}\nLicense-Expression: MIT\nLicense-File: LICENSE.txt\n')
        (info/'RECORD').write_text(f'sample-1.0.dist-info/METADATA,,\n{notice},,\n')
        target=site/notice; target.parent.mkdir(parents=True,exist_ok=True); target.write_text('fixture license\n')
        package=site/'sample'; package.mkdir(); (package/'__init__.py').write_text("raise RuntimeError('Package must not be imported')\n")
        lock=root/'requirements.lock'; lock.write_text('sample==1.0\n')
        return root/'environment/bin/python', lock

    def test_collects_metadata_and_hash_without_importing_package(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); python,lock=self.fixture(root)
            with patch.object(inventory,'ROOT',root): result=inventory.inspect_environment(python,lock)
            self.assertEqual(result['count'],1); self.assertEqual(result['packagesWithoutNoticeFiles'],[])
            row=result['packages'][0]
            self.assertEqual(row['licenseExpression'],'MIT')
            self.assertEqual(row['installedNoticeFiles'][0]['sha256'],hashlib.sha256(b'fixture license\n').hexdigest())
            self.assertIsNotNone(row['metadataSHA256'])

    def test_installed_version_mismatch_stops(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); python,lock=self.fixture(root,version='2.0')
            with self.assertRaises(ValueError): inventory.inspect_environment(python,lock)

    def test_notice_outside_environment_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); python,lock=self.fixture(root,notice='../LICENSE')
            with self.assertRaises(ValueError): inventory.inspect_environment(python,lock)

    def test_exact_pins_and_duplicate_normalized_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock=Path(tmp)/'requirements.lock'
            for text in ['example>=1.0\n','example==1.0; python_version<"3.12"\n','a_b==1\na-b==2\n','']:
                lock.write_text(text)
                with self.subTest(text=text),self.assertRaises(ValueError): inventory.pinned(lock)


if __name__=='__main__': unittest.main()
