# Exact Sequoia 15.7.9 installer builder

Scripts only. Pinned Apple package: **15.7.9 / 24G830**, 15,655,958,320 bytes.
SHA-256: `3a0d0ce4422a51b826699508a50e3f6b559cff7014daaa5b3600bbef935ecc9e`.

## Current workflow: preflight only

Manual dispatch uses standard **macos-15-intel**, never a larger runner. It verifies Intel execution, required tools and official package availability/size. It does **not** prove the package contents or build an installer.

A full build is deliberately NOT wired into Actions until a private authenticated delivery destination is approved and configured. Public-repository artifacts are not private merely because downloads require login: repository read access suffices. No artifacts, caches, releases, macOS binaries, hardware identifiers or credentials are published here. No billing configuration changes are required.

GitHub documents standard public runners as free. Storage has separate rules; this workflow avoids artifact/cache storage altogether:
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://docs.github.com/en/actions/managing-workflow-runs/downloading-workflow-artifacts

## Build script

`scripts/build.sh` is provided for a suitable Intel macOS machine with at least 65 GiB free. It downloads only the pinned package, checks full hash/size and Apple signature, installs the app, validates embedded update metadata, creates a disk-backed GPT/HFS+ image, runs Apple's createinstallmedia, and validates partition/boot structure. It does not upload anything. Do not run in ephemeral CI without an approved delivery path.

The final image has no personalized OpenCore EFI; add that privately after retrieval. Static structural checks are not a target-hardware boot test. A recovery-only BaseSystem is not substituted for the full installer.
