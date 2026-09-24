# Runtime dependency inventory

September 23, 2026. [Machine-readable inventory](dependency-inventory.json)
records the installed packages matching both runtime lockfiles: 25 parser
entries and 60 vision entries. Shared dependencies appear in both environments,
possibly at different versions. Every inventoried version matched its pin.

The inventory records wheel METADATA hashes, declared license expressions and
classifiers, and the paths/hashes of detected installed license/notice files.
It does not import packages, load models, install anything or operate the app.
The four scanner tests cover metadata/notice hashes without package import,
version mismatch, an out-of-environment notice path, and invalid/duplicate pins.

## Supplemental upstream records

The scanner found no license/notice file in these packages' RECORD entries using
its current filename matching. This is a review gap, not a claim that these
packages lack a license. The declarations below come from installed metadata.

The corresponding root licenses have now been retrieved from all four exact
release tags. Each tag was resolved to an immutable commit and every downloaded
file matched the upstream Git blob hash. [Source records](runtime-upstream/sources.json)
retain the tag, commit, URL, SHA-256 and blob hash; the installed inventory is
preserved as originally observed.

| Environment | Package/version | Recovered root license |
| --- | --- | --- |
| Parser | safetensors 0.3.1 | [Apache 2.0](runtime-upstream/safetensors-0.3.1-LICENSE.txt) |
| Parser | tokenizers 0.13.3 | [Apache 2.0](runtime-upstream/tokenizers-0.13.3-LICENSE.txt) |
| Vision | sentencepiece 0.2.2 | [Apache 2.0](runtime-upstream/sentencepiece-0.2.2-LICENSE.txt) |
| Vision | tokenizers 0.23.2 | [Apache 2.0](runtime-upstream/tokenizers-0.23.2-LICENSE.txt) |

Before distributing a bundled runtime, inspect native-library notices in larger wheels such as
PyTorch, NumPy, SciPy and OpenCV. A package's top-level license expression is not
a complete inventory of its embedded libraries. Some wheel license fields also
contain long text; the inventory preserves a hash and first-line preview rather
than treating that preview as a legal classification.

The inventory excludes Python itself, macOS frameworks, browser development
dependencies and separately bundled model assets. Existing BERT/GoClick notices
are tracked in [MODEL-NOTICES.txt](MODEL-NOTICES.txt). Local Voice's original
source uses [MIT](../LICENSE); that choice does not alter dependency terms.
No compatibility or redistribution-clearance conclusion is implied.

## Reproducible notice archive

`local-voice-runtime-notices-2026-09-23.tar.gz` packages 262 inventoried installed
notice files and the four supplemental root licenses, with a manifest associating
all 85 pinned package entries to their files. The archive is 321,646 bytes,
SHA-256 `fd3b86b778c3ce0b7e54b3f6050e573d0899e113794722f35b0c176bc19f8a50`.
All member names and content hashes verified; re-export was byte-identical.
Eight inventory/packaging tests passed, including changed-file, missing-notice,
traversal and output-preservation cases. [Archive evidence](runtime-notices-evidence.json)
records exact input/source hashes.

This is an unpublished review archive, not a complete component audit. It
preserves full detected notice text without truncation or replacing authors'
copyright statements. No runtime binaries or models are included, and the app
still uses separately installed Python environments.

## Reproduce

```sh
python3.11 voice/tools/inventory_dependency_licenses.py --runtime-config /path/to/runtime/runtime.json --output /path/to/new-inventory.json
python3.11 -m unittest discover -s voice/licenses -p test_inventory.py -v
python3.11 voice/tools/pack_runtime_notices.py --inventory voice/licenses/dependency-inventory.json --runtime-config /path/to/runtime/runtime.json --upstream voice/licenses/runtime-upstream/sources.json --upstream-root voice/licenses --output /path/to/new-notices.tar.gz
python3.11 -m unittest discover -s voice/licenses -p 'test_*.py' -v
```

The scanner requires an isolated installed environment matching each lock. It
rejects mismatched versions and preserves an existing output. Its source hash
and both lockfile hashes are included in the report. The r7 source snapshot
includes this review artifact, tooling and four supplemental licenses. The
larger installed-notice archive is supplied separately; it is not required to
run the app or rebuild source.
