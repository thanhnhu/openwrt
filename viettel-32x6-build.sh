#!/bin/bash
# Build OpenWrt for Viettel vAP-32X6V1 inside WSL (ext4). Log: ~/owrt-32x6/build-32x6.log
set -euo pipefail
# WSL appends the Windows PATH ("Program Files (x86)" ...); the "(" breaks the
# U-Boot make command line, so build with a Linux-only PATH.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# WSL's DNS proxy (10.255.255.254) is too slow for download.pl's 5 s timeout
if ! timeout 3 getent ahostsv4 sources.cdn.openwrt.org >/dev/null; then
  echo "DNS too slow/broken in WSL ($(grep -m1 nameserver /etc/resolv.conf))." >&2
  echo "Fix: sudo chattr -i /etc/resolv.conf; printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf; sudo chattr +i /etc/resolv.conf" >&2
  exit 3
fi
bash "$(cd "$(dirname "$0")" && pwd)/viettel-32x6-sync-wsl.sh"
cd ~/owrt-32x6
exec > >(tee build-32x6.log) 2>&1
echo "== feeds $(date)"
./scripts/feeds update -a
./scripts/feeds install -a
cp viettel-32x6.diffconfig .config
make defconfig
echo "== missing from .config:"
grep -E '^CONFIG_' viettel-32x6.diffconfig | while read -r l; do grep -qxF "$l" .config || echo "  $l"; done
echo "== download $(date)"
for i in 1 2 3; do make download -j16 && break; echo "download retry $i"; sleep 10; done
echo "== build $(date)"
make -j"$(nproc)" || make -j1 V=s
echo "== done $(date)"
ls -la bin/targets/mediatek/filogic/ | grep -i viettel
