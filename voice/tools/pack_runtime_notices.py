"""Package explicitly inventoried public dependency notices for release review."""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import tarfile
import tempfile

MAX_FILE = 2_000_000
MAX_TOTAL = 12_000_000


def digest(data):
    return hashlib.sha256(data).hexdigest()


def relative(value):
    if not isinstance(value,str) or not value or '\\' in value or '\0' in value:
        raise ValueError('Invalid notice path')
    name=PurePosixPath(value)
    if name.is_absolute() or str(name)!=value or any(p in {'','.','..'} for p in value.split('/')):
        raise ValueError('Notice paths must be canonical and relative')
    return name


def checked(root, record):
    name=relative(record['path']); root=Path(root).resolve()
    path=root.joinpath(*name.parts).resolve()
    try:path.relative_to(root)
    except ValueError:raise ValueError('Notice leaves its declared source directory') from None
    if not path.is_file() or path.stat().st_size>MAX_FILE:raise ValueError('Missing or oversized notice')
    data=path.read_bytes()
    if len(data)!=record['bytes'] or digest(data)!=record['sha256']:
        raise ValueError('Notice no longer matches inventory')
    text=data.decode('utf-8')
    if '\0' in text:raise ValueError('Binary content is not a notice')
    return data


def collect(inventory, runtime, upstream, upstream_root):
    files={}; packages=[]; supplemental={(r['package'],r['version']):r for r in upstream['records']}
    if len(supplemental)!=len(upstream['records']):raise ValueError('Duplicate supplemental package')
    for kind,environment in inventory['environments'].items():
        if kind not in ['parser','vision']:raise ValueError('Unknown runtime environment')
        root=Path(runtime[kind+'Python']).absolute().parent.parent
        sites=list((root/'lib').glob('python*/site-packages'))
        if len(sites)!=1:raise ValueError('Expected one isolated package directory')
        for package in environment['packages']:
            package_key=package['name']+'-'+package['version']; relative(package_key)
            if '/' in package_key:raise ValueError('Invalid package name/version')
            members=[]
            for record in package['installedNoticeFiles']:
                target=f'installed/{kind}/{package_key}/{record["path"]}'; relative(target)
                if target in files:raise ValueError('Duplicate notice destination')
                files[target]=checked(sites[0],record); members.append(target)
            sources=[]
            for record in supplemental.get((package['name'],package['version']),{}).get('files',[]):
                target='upstream/'+record['path']; relative(target)
                data=checked(upstream_root,record)
                if target in files and files[target]!=data:raise ValueError('Conflicting upstream notice')
                files[target]=data; members.append(target); sources.append(record['url'])
            if not members:raise ValueError('No inventoried or supplemental notice for a pinned package')
            packages.append(dict(environment=kind,name=package['name'],version=package['version'],
                licenseExpression=package['licenseExpression'],licenseClassifiers=package['licenseClassifiers'],
                noticeFiles=members,upstreamURLs=sources))
    if sum(map(len,files.values()))>MAX_TOTAL:raise ValueError('Notice archive exceeds size limit')
    manifest=dict(version=1,status='unpublished dependency-notice review snapshot',packages=packages,
        files={name:dict(bytes=len(data),sha256=digest(data)) for name,data in sorted(files.items())},
        scope='Explicitly inventoried wheel notice files plus pinned upstream root licenses. '
              'Not a complete embedded-library audit or compatibility/redistribution determination. '
              'No binaries, models, local configuration or Python interpreter license included.')
    files['MANIFEST.json']=(json.dumps(manifest,indent=2,sort_keys=True)+'\n').encode()
    files['UPSTREAM-SOURCES.json']=(json.dumps(upstream,indent=2,sort_keys=True)+'\n').encode()
    files['README.txt']=(
        'Local Voice runtime dependency notices — review snapshot\n\n'
        'The exact license/notice bytes are retained under installed/ and upstream/.\n'
        'MANIFEST.json associates each pinned package with its notices and their hashes.\n'
        'UPSTREAM-SOURCES.json records exact release tags, commits and Git blob hashes.\n'
        'This snapshot is not a complete embedded-library audit or a legal clearance.\n'
        'It excludes models, binaries, the Python interpreter and macOS frameworks.\n'
        'The application still uses separately installed Python dependencies.\n'
    ).encode()
    return files,manifest


def write(files,output):
    output=Path(output)
    if output.exists() or output.is_symlink():raise FileExistsError('Do not overwrite existing review artifacts')
    output.parent.mkdir(parents=True,exist_ok=True); temporary=None
    try:
        with tempfile.NamedTemporaryFile(prefix='.runtime-notices-',dir=output.parent,delete=False) as stream:
            temporary=Path(stream.name)
            with gzip.GzipFile(filename='',mode='wb',fileobj=stream,mtime=0,compresslevel=9) as zipped:
                with tarfile.open(fileobj=zipped,mode='w',format=tarfile.PAX_FORMAT) as archive:
                    for name,data in sorted(files.items()):
                        relative(name)
                        member=tarfile.TarInfo('local-voice-runtime-notices/'+name)
                        member.size=len(data);member.mode=0o644;member.mtime=0
                        member.uid=member.gid=0;member.uname=member.gname=''
                        archive.addfile(member,io.BytesIO(data))
            stream.flush();os.fsync(stream.fileno())
        os.link(temporary,output)
    finally:
        if temporary is not None:temporary.unlink(missing_ok=True)
    return dict(bytes=output.stat().st_size,sha256=digest(output.read_bytes()))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--inventory',type=Path,required=True)
    parser.add_argument('--runtime-config',type=Path,required=True);parser.add_argument('--upstream',type=Path,required=True)
    parser.add_argument('--upstream-root',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    inventory=json.loads(args.inventory.read_text());runtime=json.loads(args.runtime_config.read_text())
    upstream=json.loads(args.upstream.read_text())
    files,manifest=collect(inventory,runtime,upstream,args.upstream_root)
    evidence=write(files,args.output)
    print(json.dumps(dict(**evidence,packages=len(manifest['packages']),noticeFiles=len(manifest['files'])),indent=2))
