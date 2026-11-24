#!/bin/bash
# Build ImmortalWrt (fork thanhnhu/immortalwrt-mt798x, workspace ImmortalWRT/) for the
# Viettel 32x6 only, in WSL. Firmware only: the router keeps the OpenWrt Multi
# Firmware U-Boot. The working tree (including uncommitted changes) is synced to
# ~/iwrt-32x6 on ext4. Result: ~/iwrt-32x6/bin/targets/mediatek/filogic/*viettel_32x6*.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SRC=/mnt/d/Working/Projects/ImmortalWRT
DST=$HOME/iwrt-32x6

[ -d "$DST/.git" ] || git clone -q "$SRC" "$DST"
cd "$DST"
git fetch -q "$SRC" HEAD && git reset -q --hard FETCH_HEAD
# uncommitted changes of the Windows tree (copied as files: a diff from the
# Windows checkout can differ in line endings)
{ git -C "$SRC" diff --name-only HEAD; git -C "$SRC" ls-files --others --exclude-standard; } |
while read -r f; do
	[ -f "$SRC/$f" ] || continue
	mkdir -p "$(dirname "$f")"; cp "$SRC/$f" "$f"; sed -i 's/\r$//' "$f"
	echo "local change: $f"
done

exec > >(tee build-32x6.log) 2>&1
echo "== prepare $(date)"
# the fork's prepare step requires both Viettel devices (32x6 + NR3053)
bash scripts/prepare-build.sh defconfig/viettel-only.config
echo "== download $(date)"
make download -j8 || make download -j1 V=s
echo "== build $(date)"
make -j"$(nproc)" || make -j1 V=s
echo "== done $(date)"
ls -la bin/targets/mediatek/filogic/ | grep -i viettel_32x6
