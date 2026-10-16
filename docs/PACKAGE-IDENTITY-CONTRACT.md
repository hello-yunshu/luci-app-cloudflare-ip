# Package identity and artifact contract

The product authority is package/luci-app-cloudflare-ip/Makefile (PKG_VERSION and
PKG_RELEASE). release-channel.json independently owns the channel. Read them with:

~~~sh
python3 -B scripts/package_identity.py
python3 -B scripts/package_identity.py --field tag
python3 -B scripts/package_identity.py --matrix
python3 -B scripts/package_identity.py --public-artifacts
~~~

contracts/package-artifacts.json owns the SDK matrix and the single public
representative for each format. Changing a supported target requires a reviewed
policy change; it must not silently change installed-package compatibility.

The build uses the same Makefile variables for all version placeholders. CLI/RPC
retain the existing base version fields and add package_version. The footer and
CSS cache identity include package release. Runtime API, engine schema, Feature
Schema and Model Generation remain independent protocol identities.

## Package metadata and publication

scripts/openwrt-package-metadata.py reads real IPK control records (ar or tar
container) or real apk adbdump JSON. It retains raw packageVersion and emits
normalized version/release, architecture, size and SHA-256. Duplicate control
fields/package records and files changing during inspection are rejected.

Historical IPK -N compatibility is retained; current audited SDK outputs use
-rN. APK uses -rN. The filename must agree with the actual raw package metadata;
no validator invents a different suffix. all/noarch acceptance is format-specific.

~~~sh
python3 -B scripts/openwrt-package-metadata.py PACKAGE --format ipk --source-root .
python3 -B scripts/openwrt-package-metadata.py PACKAGE --format apk --source-root . --apk-bin /path/to/apk
python3 -B scripts/check-package-assets.py /path/to/same-run-sdk-artifact-directories
bash tests/release-asset-contract.sh /path/to/release-directory
python3 -B tests/real-package-identity.py /path/to/same-run-sdk-artifact-directories
~~~

The APK fallback adapter uses the native apk when available, otherwise a
read-only bind mount in an ephemeral alpine:3.23 Docker container. It never
installs the inspected package. Tool availability is required; missing Docker/apk
is an explicit failure, never synthetic metadata or a skipped successful test.

The SDK artifact check requires exactly the registry's artifact directories,
inspects every real main package and compares its entire sidecar to actual
metadata/bytes. The release validator binds the exact commit/run, contract,
basename, metadata, size and hash, re-reads actual package contents and rejects
extra/nested/duplicate/symlink packages. The checksum contract requires exactly
one relative entry per bound public package.

The existing SDK development mapping is centralized in --build-version --format:
APK maps the source -dev suffix to the established numeric .1 build suffix;
IPK retains -dev. Such development outputs do not authorize release promotion.
The explicit Stable gate and current channel remain unchanged.

## Upgrade ordering and immutable history

Use the real package manager, not string/semver ordering:

~~~sh
python3 -B scripts/package_identity.py --upgrade-from INSTALLED_RAW_VERSION --format ipk --manager /path/to/opkg
python3 -B scripts/package_identity.py --upgrade-from INSTALLED_RAW_VERSION --format apk --manager /path/to/apk
~~~

The opkg strict operator is >> (a single > accepts equality in the audited
OpenWrt tool). APK requires version -t to return >. Equal versions and downgrades
are rejected. G7 must apply this against the actual installed/published versions;
these commands alone are not installation or migration proof.

Historical migration tags, SHAs and hashes remain immutable fixtures.
contracts/rill-runtime.json remains a reviewed, qualified immutable dependency
pin. Sync updates only owned dependency fields, preserves migration and nested
extensions, validates the candidate and serialized temporary file before atomic
replacement, preserves file permissions, and leaves an exact no-op unchanged.
Unknown schema, invalid package release/recipe and unavailable qualification
cannot produce a successful rewritten contract. Remote PR automation and
Runtime security/byte provenance are separate G2/G3 work.

## Test evidence levels

tests/package-identity-contract.py exercises future source changes, actual GNU
Make macro expansion, compiled CLI/RPC version responses, unknown/invalid
identities, format ambiguity, target selection, sync extension preservation,
no-op, failed qualification, invalid schema and injected atomic-write failure.

tests/package_contract_fixtures.py supplies explicitly synthetic byte-binding
fixtures. tests/release-asset-binding.sh mocks only the metadata reader to isolate
byte/path binding; it is not proof of a valid package. The SDK job and
tests/real-package-identity.py exercise the same production validators with
unmocked real packages and a real APK tool. The latter constructs a validator
test manifest; it never changes the original source-run qualification verdict.

Run the focused source checks before remote CI. A local working-tree result is
not same-SHA hosted CI, a new SDK build, installed-device acceptance or a Release.

