import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import model_assets as assets


class ModelAssetTests(unittest.TestCase):
    def fixture(self, root):
        app = root / "Local Voice.app"
        runtime = app / "Contents/Resources/Runtime"
        files = {}
        self.payloads = {}
        for name in assets.COMMAND_FILES | assets.VISION_FILES | assets.NOTICE_FILES:
            data = ("fixture: " + name).encode()
            target = runtime / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            files[name] = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
            self.payloads[name] = data
        lock = dict(version=1,
                    commands=dict(files={name: files[name] for name in assets.COMMAND_FILES}),
                    vision=dict(repo="HongxinLi/GoClick-Base", revision="a" * 40,
                                files={name: files[name] for name in assets.VISION_FILES}),
                    notices={name: files[name] for name in assets.NOTICE_FILES})
        return app, runtime, lock

    def archive(self, root, lock, extra=None, omit=None, corrupt=None):
        path = root / "commands.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for name in sorted(assets.COMMAND_FILES | assets.NOTICE_FILES):
                if name == omit:
                    continue
                data = self.payloads[name]
                if name == corrupt:
                    data = b"x" * len(data)
                info = tarfile.TarInfo(name)
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
            if extra is not None:
                archive.addfile(extra)
        return path

    def test_export_is_reproducible_and_excludes_unlisted_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app, runtime, lock = self.fixture(root)
            (runtime / "private.txt").write_text("private")
            first = assets.export_commands(app, root / "a.tar.gz", lock)
            second = assets.export_commands(app, root / "b.tar.gz", lock)
            self.assertEqual(first["sha256"], second["sha256"])
            with tarfile.open(root / "a.tar.gz") as archive:
                self.assertEqual(set(archive.getnames()), assets.COMMAND_FILES | assets.NOTICE_FILES)
                self.assertTrue(all(member.uid == 0 and member.mtime == 0 and not member.uname
                                    for member in archive.getmembers()))
            with self.assertRaises(FileExistsError):
                assets.export_commands(app, root / "a.tar.gz", lock)

    def test_export_rejects_modified_and_external_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app, runtime, lock = self.fixture(root)
            weight = runtime / "models/parser.pt"
            weight.write_bytes(b"modified")
            with self.assertRaises(ValueError):
                assets.export_commands(app, root / "bad.tar.gz", lock)
            outside = root / "outside.pt"
            outside.write_bytes(self.payloads["models/parser.pt"])
            weight.unlink()
            weight.symlink_to(outside)
            with self.assertRaises(ValueError):
                assets.export_commands(app, root / "bad.tar.gz", lock)
            self.assertFalse((root / "bad.tar.gz").exists())

    def test_prepares_without_app_or_research_directory(self):
        with tempfile.TemporaryDirectory(prefix="clean assets ") as temp:
            root = Path(temp)
            _, runtime, lock = self.fixture(root)
            archive = self.archive(root, lock)
            cache = runtime / "models/goclick"
            result = assets.prepare(archive, root / "prepared", cache, lock)
            source, files = assets.verify_pack(Path(result["assets"]), lock)
            self.assertEqual(set(files), assets.COMMAND_FILES | assets.VISION_FILES)
            self.assertTrue((source / "licenses/MODEL-NOTICES.txt").is_file())
            self.assertNotIn(str(root), (source / "manifest.json").read_text())
            self.assertTrue(assets.prepare(root / "not-needed", root / "prepared", lock=lock)["reused"])

    def test_archive_rejects_paths_links_duplicates_and_extras(self):
        bad_members = []
        for name in ("../escaped", "/tmp/escaped", "models/private.txt", "models/parser.pt"):
            bad_members.append(tarfile.TarInfo(name))
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.DIRTYPE):
            member = tarfile.TarInfo("models/parser.pt")
            member.type = kind
            member.linkname = "../../escaped"
            bad_members.append(member)
        for member in bad_members:
            with self.subTest(name=member.name, kind=member.type), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                _, runtime, lock = self.fixture(root)
                archive = self.archive(root, lock, extra=member)
                with self.assertRaises(ValueError):
                    assets.prepare(archive, root / "prepared", runtime / "models/goclick", lock)
                self.assertEqual(list((root / "prepared").iterdir()), [])
                self.assertFalse((root / "escaped").exists())

    def test_corrupt_or_incomplete_archive_publishes_nothing(self):
        for kwargs in (dict(corrupt="models/parser.pt"), dict(omit="models/parser.pt")):
            with self.subTest(kwargs=kwargs), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                _, runtime, lock = self.fixture(root)
                archive = self.archive(root, lock, **kwargs)
                with self.assertRaises(ValueError):
                    assets.prepare(archive, root / "prepared", runtime / "models/goclick", lock)
                self.assertEqual(list((root / "prepared").iterdir()), [])

    def test_corrupt_vision_cache_does_not_publish(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, runtime, lock = self.fixture(root)
            (runtime / "models/goclick/model.safetensors").write_bytes(b"corrupt")
            archive = self.archive(root, lock)
            with self.assertRaises(ValueError):
                assets.prepare(archive, root / "prepared", runtime / "models/goclick", lock)
            self.assertEqual(list((root / "prepared").iterdir()), [])

    def test_downloads_only_pinned_files_and_recovers_after_interruption(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, _, lock = self.fixture(root)
            archive = self.archive(root, lock)
            with patch("model_assets.urllib.request.build_opener") as build:
                build.return_value.open.side_effect = TimeoutError("interrupted")
                with self.assertRaises(TimeoutError):
                    assets.prepare(archive, root / "prepared", lock=lock)
                self.assertEqual(list((root / "prepared").iterdir()), [])
                def download(url, timeout):
                    prefix = "https://huggingface.co/HongxinLi/GoClick-Base/resolve/" + "a" * 40 + "/"
                    self.assertTrue(url.startswith(prefix))
                    name = "models/goclick/" + url.removeprefix(prefix)
                    return io.BytesIO(self.payloads[name])
                build.return_value.open.side_effect = download
                result = assets.prepare(archive, root / "prepared", lock=lock)
            self.assertTrue(Path(result["assets"]).is_dir())

    def test_existing_package_is_rechecked_against_lock_not_its_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, runtime, lock = self.fixture(root)
            archive = self.archive(root, lock)
            result = assets.prepare(archive, root / "prepared", runtime / "models/goclick", lock)
            package = Path(result["assets"])
            (package / "models/parser.pt").write_bytes(b"modified")
            manifest = json.loads((package / "manifest.json").read_text())
            manifest["files"]["models/parser.pt"] = hashlib.sha256(b"modified").hexdigest()
            (package / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                assets.prepare(archive, root / "prepared", lock=lock)

    def test_download_length_and_hash_are_bounded(self):
        for data in (b"a", b"aaa", b"bb"):
            with self.subTest(data=data), tempfile.TemporaryDirectory() as temp:
                entry = dict(bytes=2, sha256=hashlib.sha256(b"aa").hexdigest())
                with self.assertRaises(ValueError):
                    assets.copy_checked(io.BytesIO(data), Path(temp) / "file", entry)

    def test_lock_and_redirect_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _, _, lock = self.fixture(root)
            path = root / "lock.json"
            path.write_text(json.dumps(lock))
            self.assertEqual(assets.load_lock(path), lock)
            lock["vision"]["revision"] = "main"
            path.write_text(json.dumps(lock))
            with self.assertRaises(ValueError):
                assets.load_lock(path)
            with self.assertRaises(ValueError):
                assets.HTTPSOnly().redirect_request(None, None, 302, "", {}, "http://example.com/asset")


if __name__ == "__main__":
    unittest.main()
