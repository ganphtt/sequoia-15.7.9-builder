#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/source.env
[[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]]
for tool in hdiutil diskutil installer pkgutil curl shasum python3; do command -v "$tool" >/dev/null; done
sw_vers
python3 - <<'PY'
import shutil
free = shutil.disk_usage('.').free
print(f'Available workspace bytes: {free}')
print('Full build requires at least 65 GiB available; this run does not download or build it.')
PY
headers=$(mktemp)
trap 'rm -f "$headers"' EXIT
curl --fail --silent --show-error --head --location --proto '=https' --tlsv1.2 --max-time 90 "$PKG_URL" > "$headers"
python3 - "$headers" "$PKG_SIZE" <<'PY'
import re, sys
s=open(sys.argv[1]).read()
lengths=re.findall(r'^content-length:\s*(\d+)',s,re.I|re.M)
assert lengths and int(lengths[-1]) == int(sys.argv[2]), 'Unexpected or missing source Content-Length'
print('Official HTTPS source reachable; exact package size matches:', lengths[-1])
PY
printf 'Pinned version=%s build=%s SHA256=%s\n' "$VERSION" "$BUILD" "$PKG_SHA256"
printf '%s\n' 'Source contents/hash/metadata are not verified by this HEAD-only preflight.'
