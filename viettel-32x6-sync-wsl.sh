#!/bin/bash
# Sync the Windows working tree (branch + uncommitted changes) into ~/owrt-32x6 (ext4)
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST=$HOME/owrt-32x6
if [ ! -d "$DST/.git" ]; then
  git clone --no-checkout "$SRC" "$DST"
  git -C "$DST" checkout -q -B build "$(git -C "$SRC" rev-parse HEAD)"
fi
cd "$DST"
git fetch -q "$SRC" "$(git -C "$SRC" rev-parse HEAD)"
git checkout -q -f FETCH_HEAD -B build
# Remove files left from the previous sync (untracked, not ignored) so a diff that
# adds them again - e.g. when they were `git add`ed on the Windows side - applies
# cleanly. Ignored build output (dl/, build_dir/, staging_dir/, feeds/, .config) is kept.
git clean -fdq
git -C "$SRC" diff HEAD --binary > /tmp/wt.diff
[ -s /tmp/wt.diff ] && git apply --whitespace=nowarn /tmp/wt.diff
git -C "$SRC" ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
  case "$f" in *.code-workspace) continue;; esac
  mkdir -p "$(dirname "$f")"; cp "$SRC/$f" "$f"
done
chmod +x package/utils/multi-firmware/files/multifw package/utils/multi-firmware/files/multifw.init package/luci-app-advanced/root/usr/libexec/hwinfo
git status --short | head -30
