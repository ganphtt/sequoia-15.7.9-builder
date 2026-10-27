#!/bin/bash
# Local-only builder. Deliberately not invoked by the public Actions workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/source.env
[[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]]
work=$(mktemp -d "${TMPDIR:-/tmp}/sequoia-build.XXXXXX")
app='/Applications/Install macOS Sequoia.app'
[[ ! -e "$app" ]] || { printf 'Refusing to replace an existing installer app.\n' >&2; exit 1; }
python3 - "$work" <<'PY'
import shutil, sys
assert shutil.disk_usage(sys.argv[1]).free >= 65*1024**3, 'Need 65 GiB free'
PY
pkg="$work/InstallAssistant.pkg"
curl --fail --location --proto '=https' --tlsv1.2 --retry 4 --output "$pkg" "$PKG_URL"
[[ "$(stat -f %z "$pkg")" == "$PKG_SIZE" ]]
printf '%s  %s\n' "$PKG_SHA256" "$pkg" | shasum -a 256 -c -
pkgutil --check-signature "$pkg" | tee "$work/signature.txt"
grep -q 'Status: signed by a certificate trusted by' "$work/signature.txt"
grep -q 'Software Update' "$work/signature.txt"
sudo installer -pkg "$pkg" -target /
[[ -x "$app/Contents/Resources/createinstallmedia" ]]
mkdir "$work/support"
disk=''
cleanup() {
  hdiutil detach "$work/support" >/dev/null 2>&1 || true
  if [[ -n "$disk" ]]; then hdiutil detach "$disk" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
hdiutil attach "$app/Contents/SharedSupport/SharedSupport.dmg" -readonly -nobrowse -mountpoint "$work/support"
python3 - "$work/support" "$VERSION" "$BUILD" <<'PY'
import pathlib, plistlib, sys
root, version, build = sys.argv[1:]
matched=[]
def visit(obj):
    if isinstance(obj,dict):
        if 'OSVersion' in obj and 'Build' in obj:
            matched.append((obj['OSVersion'],obj['Build']))
        for v in obj.values(): visit(v)
    elif isinstance(obj,list):
        for v in obj: visit(v)
for p in pathlib.Path(root).rglob('com_apple_MobileAsset_MacSoftwareUpdate.xml'):
    visit(plistlib.loads(p.read_bytes()))
assert matched and all(v == (version,build) for v in matched), matched
print('Verified embedded OSVersion/Build:', matched)
PY
hdiutil detach "$work/support"
rm "$pkg"
image="$work/Sequoia-${VERSION}-${BUILD}.img"
# A raw regular file, not a RAM disk or a DMG container.
mkfile -n 24g "$image"
hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount -plist "$image" > "$work/attach.plist"
disk=$(python3 - "$work/attach.plist" <<'PY'
import plistlib,sys
p=plistlib.load(open(sys.argv[1],'rb'))
devices=[v['dev-entry'] for v in p['system-entities'] if v.get('dev-entry')]
assert len(devices)==1, devices
print(devices[0])
PY
)
[[ "$disk" =~ ^/dev/disk[0-9]+$ ]]
sudo diskutil partitionDisk "$disk" GPT JHFS+ SequoiaBuild 100%
sudo "$app/Contents/Resources/createinstallmedia" --volume /Volumes/SequoiaBuild --nointeraction
sudo diskutil verifyDisk "$disk"
diskutil list -plist "$disk" > "$work/partitions.plist"
python3 - "$work/partitions.plist" <<'PY'
import plistlib,sys
p=plistlib.load(open(sys.argv[1],'rb'))['AllDisksAndPartitions'][0]
assert p['Content']=='GUID_partition_scheme', p
parts=p['Partitions']
assert any(x['Content']=='EFI' for x in parts)
assert any(x['Content']=='Apple_HFS' for x in parts)
print('Verified GPT, EFI system partition and HFS+ installer partition')
PY
vol='/Volumes/Install macOS Sequoia'
[[ -d "$vol/Install macOS Sequoia.app" ]]
[[ -f "$vol/.IABootFiles/boot.efi" || -f "$vol/System/Library/CoreServices/boot.efi" ]]
sudo diskutil verifyVolume "${disk}s2"
sync
hdiutil detach "$disk"
disk=''
shasum -a 256 "$image" | tee "$work/image.sha256"
printf 'Built and structurally checked: %s\nNo upload performed. Target-hardware boot NOT tested.\n' "$image"
