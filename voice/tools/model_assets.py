#!/usr/bin/env python3
"""Export pinned command weights, or prepare model assets without an existing app.

Only preparation may download: it fetches the pinned GoClick files from Hugging
Face. Neither operation imports ML libraries, executes downloaded code, starts
the app, or changes an installed runtime configuration.
"""
import argparse
import errno
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "voice/models/models.lock.json"
COMMAND_FILES = {
    "models/base/config.json", "models/base/vocab.txt", "models/source.json",
    "models/parser.pt", "models/operation.pt", "models/ranker.pt",
}
VISION_FILES = {"models/goclick/" + name for name in (
    "model.safetensors", "config.json", "preprocessor_config.json",
    "tokenizer.json", "tokenizer_config.json", "vocab.json",
    "generation_config.json", "README.md",
)}
NOTICE_FILES = {"licenses/" + name for name in (
    "BERT-Apache-2.0.txt", "GoClick-MIT.txt", "MODEL-NOTICES.txt", "sources.json",
)}


def load_lock(path=LOCK):
    lock = json.loads(Path(path).read_text())
    if not isinstance(lock, dict) or lock.get("version") != 1:
        raise ValueError("Unsupported model lock")
    for group, expected in (("commands", COMMAND_FILES), ("vision", VISION_FILES)):
        section = lock.get(group)
        if (not isinstance(section, dict) or not isinstance(section.get("files"), dict)
                or set(section["files"]) != expected):
            raise ValueError(f"Model lock has an unexpected {group} file list")
    if not isinstance(lock.get("notices"), dict) or set(lock["notices"]) != NOTICE_FILES:
        raise ValueError("Model lock has an unexpected notice file list")
    for entry in all_files(lock).values():
        if (not isinstance(entry, dict)
                or type(entry.get("bytes")) is not int or entry["bytes"] <= 0
                or not isinstance(entry.get("sha256"), str)
                or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"])):
            raise ValueError("Invalid model lock size or SHA256")
    vision = lock["vision"]
    if (vision.get("repo") != "HongxinLi/GoClick-Base"
            or not re.fullmatch(r"[0-9a-f]{40}", str(vision.get("revision", "")))):
        raise ValueError("Vision must refer to a pinned GoClick revision")
    return lock


def all_files(lock):
    return {**lock["commands"]["files"], **lock["vision"]["files"], **lock["notices"]}


def lock_identity(lock):
    return hashlib.sha256(json.dumps(lock, sort_keys=True).encode()).hexdigest()


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_file(path, entry):
    if (not path.is_file() or path.stat().st_size != entry["bytes"]
            or digest(path) != entry["sha256"]):
        raise ValueError(f"Pinned asset is missing or changed: {path.name}")


def verify_pack(directory, lock=None):
    lock = lock or load_lock()
    directory = Path(directory).resolve()
    for name, entry in all_files(lock).items():
        path = directory / name
        if not path.resolve().is_relative_to(directory):
            raise ValueError("Model asset leaves its package directory")
        verify_file(path, entry)
    # The source-controlled lock, not an archive-supplied manifest, establishes
    # the accepted hashes. Only these model files may enter the installed store.
    files = {name: entry["sha256"] for name, entry in all_files(lock).items()
             if name.startswith("models/")}
    return directory, files


def copy_checked(stream, target, entry):
    target.parent.mkdir(parents=True, exist_ok=True)
    remaining = entry["bytes"]
    hasher = hashlib.sha256()
    with target.open("xb") as output:
        while remaining:
            block = stream.read(min(1024 * 1024, remaining))
            if not block:
                raise ValueError(f"Truncated asset: {target.name}")
            remaining -= len(block)
            output.write(block)
            hasher.update(block)
        if stream.read(1):
            raise ValueError(f"Oversized asset: {target.name}")
    if hasher.hexdigest() != entry["sha256"]:
        raise ValueError(f"Pinned asset hash mismatch: {target.name}")


def export_commands(app, output, lock=None):
    lock = lock or load_lock()
    source = Path(app).resolve() / "Contents/Resources/Runtime"
    files = {**lock["commands"]["files"], **lock["notices"]}
    for name, entry in files.items():
        if not (source / name).resolve().is_relative_to(source):
            raise ValueError("Source asset leaves the app bundle")
        verify_file(source / name, entry)
    output = Path(output).absolute()
    if output.exists():
        raise FileExistsError("Output already exists; choose a new archive path")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".commands-", dir=output.parent) as temp:
        archive_path = Path(temp) / "commands.tar.gz"
        with archive_path.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as zipped:
                with tarfile.open(fileobj=zipped, mode="w|") as archive:
                    for name, entry in sorted(files.items()):
                        # Verify a private copy so a concurrent app rebuild cannot
                        # produce an archive that differs from the pinned lock.
                        staged = Path(temp) / name
                        with (source / name).open("rb") as stream:
                            copy_checked(stream, staged, entry)
                        info = tarfile.TarInfo(name)
                        info.size = entry["bytes"]
                        info.mode = 0o644
                        with staged.open("rb") as stream:
                            archive.addfile(info, stream)
        # Exclusive creation never overwrites another process's release file.
        with archive_path.open("rb") as stream, output.open("xb") as destination:
            try:
                shutil.copyfileobj(stream, destination)
            except BaseException:
                output.unlink(missing_ok=True)
                raise
    return dict(archive=str(output), bytes=output.stat().st_size, sha256=digest(output))


def unpack_commands(archive_path, destination, lock):
    expected = {**lock["commands"]["files"], **lock["notices"]}
    seen = set()
    with tarfile.open(archive_path, "r|gz") as archive:
        for member in archive:
            if member.name not in expected or member.name in seen or not member.isfile():
                raise ValueError("Command archive contains an unexpected, duplicate or linked member")
            entry = expected[member.name]
            if member.size != entry["bytes"]:
                raise ValueError("Command archive member size differs from the pinned lock")
            with archive.extractfile(member) as stream:
                copy_checked(stream, destination / member.name, entry)
            seen.add(member.name)
    if seen != set(expected):
        raise ValueError("Command archive is missing required model files or notices")


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        if not newurl.startswith("https://"):
            raise ValueError("Refusing an insecure model-download redirect")
        return super().redirect_request(request, fp, code, message, headers, newurl)


def prepare(commands, directory, vision_cache=None, lock=None):
    lock = lock or load_lock()
    directory = Path(directory).absolute()
    directory.mkdir(parents=True, exist_ok=True)
    identity = lock_identity(lock)
    final = directory / ("assets-" + identity[:16])
    if final.exists():
        verify_pack(final, lock)
        return dict(assets=str(final), reused=True, lockSHA256=identity)
    with tempfile.TemporaryDirectory(prefix=".assets-", dir=directory) as temp:
        staged = Path(temp) / "assets"
        staged.mkdir()
        unpack_commands(commands, staged, lock)
        opener = urllib.request.build_opener(HTTPSOnly())
        for name, entry in sorted(lock["vision"]["files"].items()):
            filename = Path(name).name
            if vision_cache is not None:
                with (Path(vision_cache) / filename).open("rb") as stream:
                    copy_checked(stream, staged / name, entry)
            else:
                vision = lock["vision"]
                url = f"https://huggingface.co/{vision['repo']}/resolve/{vision['revision']}/{filename}"
                with opener.open(url, timeout=30) as stream:
                    copy_checked(stream, staged / name, entry)
        manifest = dict(version=1, visionIncluded=True, modelLockSHA256=identity,
                        files={name: entry["sha256"] for name, entry in all_files(lock).items()})
        (staged / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        verify_pack(staged, lock)
        try:
            staged.rename(final)
        except OSError as error:
            # Concurrent installers may prepare the same immutable asset set.
            if error.errno not in (errno.EEXIST, errno.ENOTEMPTY):
                raise
            verify_pack(final, lock)
    return dict(assets=str(final), reused=False, lockSHA256=identity)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    export = sub.add_parser("export", help="Maintainer: create the pinned command-model archive")
    export.add_argument("--from-app", required=True, type=Path)
    export.add_argument("--output", required=True, type=Path)
    setup = sub.add_parser("prepare", help="Prepare command and vision assets for a fresh checkout")
    setup.add_argument("--commands", required=True, type=Path, help="Pinned command-model .tar.gz")
    setup.add_argument("--directory", required=True, type=Path)
    setup.add_argument("--vision-cache", type=Path, help="Optional existing GoClick snapshot; hashes still checked")
    args = parser.parse_args()
    if args.command == "export":
        result = export_commands(args.from_app, args.output)
    else:
        result = prepare(args.commands, args.directory, args.vision_cache)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
