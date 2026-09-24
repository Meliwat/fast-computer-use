"""Read pinned installed-wheel metadata without importing packages or executing apps.

This inventory is factual input to release review, not a compatibility verdict.
Only packages named in the two runtime lockfiles are read. No package install,
network access, environment mutation or automatic publication occurs.
"""
import argparse
import hashlib
from importlib import metadata
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(name):
    return re.sub(r'[-_.]+', '-', name).lower()


def pinned(lock):
    result = {}
    for line in lock.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'): continue
        match = re.fullmatch(r'([A-Za-z0-9_.-]+)==([^\s;]+)', line.strip())
        if not match: raise ValueError('Expected an exact unconditional package pin')
        name, version = match.groups(); key = canonical(name)
        if key in result: raise ValueError('Duplicate normalized package pin')
        result[key] = version
    if not result: raise ValueError('No pinned packages')
    return result


def inspect_environment(python, lock):
    environment = Path(python).absolute().parent.parent
    sites = list((environment/'lib').glob('python*/site-packages'))
    if len(sites) != 1: raise ValueError('Expected one isolated site-packages directory')
    site = sites[0].resolve()
    installed = {}
    for distribution in metadata.distributions(path=[str(site)]):
        name = distribution.metadata.get('Name')
        if not name: continue
        key = canonical(name)
        if key in installed: raise ValueError('Ambiguous installed package metadata')
        installed[key] = distribution
    packages = []
    for name, version in sorted(pinned(lock).items()):
        distribution = installed.get(name)
        if distribution is None or distribution.version != version:
            raise ValueError(f'Installed version does not match lock: {name}=={version}')
        info = distribution.metadata
        files = distribution.files or []
        notices = []
        metadata_hash = None
        for relative in files:
            filename = Path(str(relative)).name
            wanted = bool(re.match(r'(?i)^(?:licen[sc]e|copying|notice)(?:[._-].*|\d*)?$', filename))
            is_metadata = filename == 'METADATA' and any(p.endswith('.dist-info') for p in Path(str(relative)).parts)
            if not wanted and not is_metadata: continue
            actual = distribution.locate_file(relative).resolve()
            try: actual.relative_to(site)
            except ValueError: raise ValueError('Package metadata/notice leaves isolated environment') from None
            if not actual.is_file(): raise ValueError('Recorded package metadata/notice is missing')
            if is_metadata: metadata_hash = digest(actual)
            if wanted:
                notices.append(dict(path=str(relative), bytes=actual.stat().st_size, sha256=digest(actual)))
        license_field = info.get('License') or ''
        packages.append(dict(name=name, version=version,
            licenseExpression=info.get('License-Expression'),
            legacyLicenseFirstLine=license_field.strip().splitlines()[0][:240] if license_field.strip() else None,
            legacyLicenseTextSHA256=hashlib.sha256(license_field.encode()).hexdigest() if license_field else None,
            licenseClassifiers=[c for c in info.get_all('Classifier', []) if c.startswith('License ::')],
            declaredLicenseFiles=info.get_all('License-File', []),
            installedNoticeFiles=notices, metadataSHA256=metadata_hash))
    return dict(lock=lock.relative_to(ROOT).as_posix(), lockSHA256=digest(lock), packages=packages,
                count=len(packages), packagesWithoutNoticeFiles=[r['name'] for r in packages if not r['installedNoticeFiles']])


def run(configuration, output):
    if output.exists(): raise FileExistsError('Retain previous review evidence')
    config = json.loads(configuration.read_text())
    result = dict(version=1, scope='Installed pinned-wheel metadata and notice hashes only. '
        'No compatibility determination or completeness claim. Does not cover Python itself, '
        'macOS frameworks, separately bundled models, browser developer dependencies, '
        'or every bundled native library within wheels. No packages imported or installed.',
        scannerSHA256=digest(Path(__file__)), environments={})
    for kind in ['parser', 'vision']:
        result['environments'][kind] = inspect_environment(config[kind+'Python'], ROOT/'voice/runtime'/f'{kind}-requirements.lock')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x') as f: f.write(json.dumps(result, indent=2)+'\n')
    print(json.dumps({kind:dict(count=value['count'], packagesWithoutNoticeFiles=value['packagesWithoutNoticeFiles'])
                      for kind,value in result['environments'].items()}, indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--runtime-config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args=parser.parse_args(); run(args.runtime_config, args.output)
