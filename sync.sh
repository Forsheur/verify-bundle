#!/bin/sh
# Copy the verifier from the Forsheur server tree into this mirror.
#
# The canonical file is `server/verifier/verify_bundle.py`: the server embeds
# it with `include_str!`, so what a bundle contains and what the server serves
# at /verifier are the same bytes by construction. This repository is a copy of
# that, and a copy is a thing that drifts.
#
# The drift that matters is not "these files differ" -- they differ every time
# the upstream is edited, which is normal. It is **the same version number on
# two different files**: a reader comparing their bundle's digest against the
# release tagged with that version would get a mismatch that means nothing, and
# would go looking for a problem in the bundle rather than in our bookkeeping.
# That is the one case this script refuses.
#
# Usage:
#   ./sync.sh              # check for drift, report, change nothing
#   ./sync.sh --apply      # copy, refusing if the version was not bumped
#
# LC_ALL=C because this runs on a machine whose locale is fr_FR, and a script
# that compares text has no business asking the locale's opinion.

set -eu
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
up="$here/../server/verifier"

[ -d "$up" ] || { echo "error: upstream not found at $up" >&2; exit 2; }

version_of() {
    sed -n 's/^VERIFIER_VERSION = "\(.*\)"$/\1/p' "$1" | head -1
}

apply=0
[ "${1:-}" = "--apply" ] && apply=1

drift=0
bump_needed=0

for f in verify_bundle.py verify_bundle.cmd verify_bundle.ps1; do
    if ! cmp -s "$up/$f" "$here/$f"; then
        drift=1
        echo "differs: $f"
        [ "$f" = "verify_bundle.py" ] && bump_needed=1
    fi
done

if [ "$drift" = 0 ]; then
    echo "in sync (version $(version_of "$here/verify_bundle.py"))"
    exit 0
fi

vu=$(version_of "$up/verify_bundle.py")
vm=$(version_of "$here/verify_bundle.py")

[ -n "$vu" ] || { echo "error: upstream declares no VERIFIER_VERSION" >&2; exit 2; }

if [ "$bump_needed" = 1 ] && [ "$vu" = "$vm" ]; then
    # The refusal. Not a warning: a published release whose version does not
    # identify its bytes defeats the only reason the version exists.
    echo "REFUSING: verify_bundle.py changed but VERIFIER_VERSION is still $vu." >&2
    echo "Bump it upstream in $up/verify_bundle.py, add a CHANGELOG entry, then re-run." >&2
    exit 1
fi

if [ "$apply" = 0 ]; then
    echo "would sync $vm -> $vu   (re-run with --apply)"
    exit 1
fi

for f in verify_bundle.py verify_bundle.cmd verify_bundle.ps1; do
    cp "$up/$f" "$here/$f"
done

echo "synced $vm -> $vu"
echo
echo "Next:"
echo "  1. add a $vu section to CHANGELOG.md"
echo "  2. commit, then: git tag v$vu && git push --tags"
echo "  3. CI publishes SHA256SUMS and the provenance attestation"
echo
sha256sum verify_bundle.py 2>/dev/null || shasum -a 256 verify_bundle.py
