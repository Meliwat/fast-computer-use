#!/usr/bin/env python3
"""Create a deterministic development source archive from an explicit file list.

No directory traversal, Git archive, secret-file reads, or automatic publication.
The allowlist is the primary boundary; text checks supplement maintainer review.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PREFIX = 'local-voice-source'
MANIFEST = 'EXPORT-MANIFEST.json'
MAX_FILE = 2_000_000
MAX_TOTAL = 12_000_000
FORBIDDEN = {'runs', '.cache', 'artifacts', 'live', 'dist', '.build',
             'node_modules', '__pycache__', '.git', '.venv', 'venv'}
GENERATED = {'native-host', 'native-host-manifest.json', 'host-config.json',
             'runtime.json', 'ParserConfig.json', 'GroundedConfig.json', 'VisionConfig.json'}
PATTERNS = {
    'API credential': re.compile(r'\bapikey_[a-zA-Z0-9]{20,}_[a-zA-Z0-9]{20,}\b'),
    'provider credential': re.compile(r'\b(?:sk-(?:proj-|ant-api\d+-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16})\b'),
    'private key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
    'absolute user path': re.compile(r'(?:/Users/|/home/)[A-Za-z0-9_.-]+/'),
}


def safe_name(value):
    if not isinstance(value,str) or not value or '\\' in value or '\0' in value:
        raise ValueError('Invalid source-list path')
    path=PurePosixPath(value)
    if path.is_absolute() or str(path)!=value or any(part in {'','..','.'} for part in value.split('/')):
        raise ValueError('Source-list paths must be canonical and relative')
    if any(part in FORBIDDEN or part.startswith('.env') for part in path.parts) or path.name in GENERATED:
        raise ValueError(f'Private/generated path is forbidden: {value}')
    if path.suffix.lower() in {'.png','.jpg','.jpeg','.mp4','.wav','.pt','.safetensors','.pem','.key','.p12','.pyc'}:
        raise ValueError(f'Binary/model/key path is forbidden: {value}')
    return path


def regular_file(root,name):
    path=root
    for part in PurePosixPath(name).parts:
        path=path/part
        if path.is_symlink():raise ValueError(f'Symlink source is forbidden: {name}')
    if not path.is_file():raise ValueError(f'Missing source file: {name}')
    if not stat.S_ISREG(path.stat().st_mode):raise ValueError(f'Non-regular source: {name}')
    if path.stat().st_size>MAX_FILE:raise ValueError(f'Source file exceeds size limit: {name}')
    return path


def inspect_text(data,name):
    try:text=data.decode('utf-8')
    except UnicodeDecodeError:raise ValueError(f'Non-text source rejected: {name}') from None
    if '\0' in text:raise ValueError(f'Binary content rejected: {name}')
    for kind,pattern in PATTERNS.items():
        match=pattern.search(text)
        if match:
            line=text.count('\n',0,match.start())+1
            # Never include a matched value in error output.
            raise ValueError(f'{kind} requires review: {name}:{line}')


def collect(root,listing):
    root=Path(root).resolve();entries=listing.get('files')
    if listing.get('version')!=1 or not isinstance(entries,list) or not entries:
        raise ValueError('Expected a non-empty version-one source list')
    files={};total=0
    for entry in entries:
        if not isinstance(entry,dict) or set(entry)-{'source','destination','executable'}:
            raise ValueError('Invalid source-list entry')
        source=str(safe_name(entry.get('source')))
        destination=str(safe_name(entry.get('destination',source)))
        if destination==MANIFEST or destination.casefold() in {n.casefold() for n in files}:
            raise ValueError(f'Duplicate/reserved archive destination: {destination}')
        if 'executable' in entry and not isinstance(entry['executable'],bool):raise ValueError('Invalid executable flag')
        path=regular_file(root,source)
        # Do not follow a replacement symlink between inspection and reading.
        descriptor=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
        with os.fdopen(descriptor,'rb') as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):raise ValueError('Source changed type')
            data=stream.read(MAX_FILE+1)
        if len(data)>MAX_FILE:raise ValueError(f'Source file exceeds size limit: {source}')
        inspect_text(data,source);total+=len(data)
        if total>MAX_TOTAL:raise ValueError('Source snapshot exceeds total size limit')
        files[destination]=(data,0o755 if entry.get('executable',False) else 0o644)
    return files


def write_archive(files,output):
    output=Path(output)
    if output.exists() or output.is_symlink():raise FileExistsError('Output already exists; choose a new path')
    manifest=dict(version=1,status='source snapshot; publication tracked by repository releases',
                  scope='Explicitly selected app, runtime and test source. No model weights, research captures, local configuration or credentials. Content-pattern checks are not a complete security/legal audit.',
                  files={name:dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),mode=oct(mode)) for name,(data,mode) in sorted(files.items())})
    archive_files={**files,MANIFEST:((json.dumps(manifest,indent=2,sort_keys=True)+'\n').encode(),0o644)}
    output.parent.mkdir(parents=True,exist_ok=True)
    temporary=None
    try:
        with tempfile.NamedTemporaryFile(prefix='.source-export-',dir=output.parent,delete=False) as stream:
            temporary=Path(stream.name)
            with gzip.GzipFile(filename='',mode='wb',fileobj=stream,mtime=0,compresslevel=9) as compressed:
                with tarfile.open(fileobj=compressed,mode='w',format=tarfile.PAX_FORMAT) as archive:
                    for name,(data,mode) in sorted(archive_files.items()):
                        info=tarfile.TarInfo(PREFIX+'/'+name)
                        info.size=len(data);info.mode=mode;info.mtime=0;info.uid=info.gid=0;info.uname=info.gname=''
                        archive.addfile(info,io.BytesIO(data))
            stream.flush();os.fsync(stream.fileno())
        # Exclusive publication: preserve an output that appeared during export.
        os.link(temporary,output)
    finally:
        if temporary is not None:temporary.unlink(missing_ok=True)
    return dict(files=len(files),bytes=output.stat().st_size,sha256=hashlib.sha256(output.read_bytes()).hexdigest())


def export(root,listing_path,output=None):
    logical_root=Path(root).absolute()
    relative=Path(listing_path).absolute().relative_to(logical_root).as_posix()
    root=logical_root.resolve()
    safe_name(relative)
    listing=json.loads(regular_file(root,relative).read_text())
    files=collect(root,listing)
    if output is None:return dict(files=len(files),uncompressedBytes=sum(len(d) for d,_ in files.values()),checked=True)
    return write_archive(files,output)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-root',type=Path,default=ROOT)
    parser.add_argument('--file-list',type=Path)
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--output',type=Path);group.add_argument('--check',action='store_true')
    args=parser.parse_args()
    try:
        result=export(args.project_root,args.file_list or args.project_root/'voice/release/source-files.json',args.output)
    except (OSError,ValueError,KeyError,TypeError) as error:
        parser.exit(1,f'Source export stopped: {error}\n')
    print(json.dumps(result,indent=2))
