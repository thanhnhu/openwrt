# Viettel vAP-32X6V1 — backup flash gốc và quay về firmware Viettel

Backup nằm ở `Why/OpenWRT/vAP-32X6V1 (netis-NX31)/Backup-32x6-240b2ae81d57-2026-11-15`.
Hướng dẫn chung: [README-viettel-32x6.md](README-viettel-32x6.md).

- Máy: MAC `24:0b:2a:e8:1d:57` (WAN) / `…:56` (LAN), backup ngày 2026-11-15.
- Firmware gốc: OpenWrt 21.02 MTK SDK r0-979fcaf31 (kernel 5.4.238), `bootflag=2`.
- NAND 128 MB (page 2048, block 128 KB), 0 bad block lúc dump; U-Boot gốc dùng NMBM.
- Dump qua SSH bằng `cat /dev/mtdN`, đã đối chiếu sha256 giữa router và PC.

## 1. Các file trong backup

| File | Offset | Kích thước | Nội dung |
|---|---|---|---|
| `mtd0_spi0.0.bin` | — | 128 MB | RAW toàn chip (gồm vùng NMBM ở cuối) |
| `mtd1_BL2.bin` | `0x0000000` | 1 MB | BL2 gốc |
| `mtd2_u-boot-env.bin` | `0x0100000` | 512 KB | env gốc (`bootflag`, `mtkboardboot`…) |
| `mtd3_Factory.bin` | `0x0180000` | 2 MB | MAC + hiệu chuẩn WiFi — **riêng máy này** |
| `mtd4_FIP.bin` | `0x0380000` | 2 MB | BL31 + U-Boot gốc |
| `mtd5_ubi.bin` | `0x0580000` | 30 MB | firmware gốc, slot 1 |
| `mtd6_ubi2.bin` | `0x2380000` | 30 MB | firmware gốc, slot 2 |
| `mtd7_data.bin` | `0x4180000` | 20 MB | dữ liệu/log Viettel (đang mount lúc dump) |
| `mtd8_ugdata.bin` | `0x5580000` | 25 MB | |
| `mtd9_config.bin` | `0x6e80000` | 5 MB | cấu hình Viettel |
| `stock-ubi-region-0x580000-end.bin` | `0x0580000` | `0x7a80000` byte | mtd0 từ `0x580000` đến hết chip — **đúng bằng phân vùng `ubi` của OpenWrt**, dùng để khôi phục |
| `stock-running.dtb` | | | device tree gốc |
| `SHA256SUMS.txt` | | | `sha256sum -c SHA256SUMS.txt` |

`mtd7_data` (và vùng data trong `mtd0`) khác checksum so với router lúc chạy là bình thường: firmware gốc ghi log liên tục. Mọi vùng khác khớp 100%.

## 2. Không dùng cho máy khác

`mtd0` và `mtd3_Factory` chứa MAC và hiệu chuẩn WiFi của **riêng máy này**; nạp sang máy khác sẽ trùng MAC và sai hiệu chuẩn. Firmware OpenWrt cho `viettel_32x6` không chứa Factory, nó đọc Factory của chính máy đó (MAC ở `0x24`/`0x2a`, EEPROM ở `0x0`), nên một bộ file flash dùng được cho mọi máy 32x6.

## 3. Quay về firmware Viettel gốc (máy này)

Thứ tự **quan trọng**: ghi vùng dữ liệu trước, FIP/BL2 **sau cùng**. Ghi FIP gốc trước thì mất U-Boot OpenWrt, không quay lại recovery để ghi tiếp được.

Số mtd trên OpenWrt: `mtd0` BL2, `mtd1` "u-boot-env (unused)", `mtd2` Factory, `mtd3` FIP, `mtd4` ubi (kiểm tra lại bằng `cat /proc/mtd`).

**Bước 0 — kiểm tra.** PC ở `192.168.1.x`, router `192.168.1.1`, SSH root được. `cat /sys/class/mtd/mtd*/bad_blocks` phải toàn `0` (`mtd write` bỏ qua block hỏng sẽ làm lệch dữ liệu; khác 0 thì dừng lại).

**Bước 1 — vào recovery** (chạy trong RAM, không dùng UBI). Không cần UART:
```bash
ssh root@192.168.1.1 'ubirename /dev/ubi0 fit fit_off && reboot'
```
U-Boot không thấy `fit` nên boot volume `recovery` trong NAND. Nếu NAND không có recovery: chạy Tftpd64 ở `192.168.1.254` với file `openwrt-mediatek-filogic-viettel_32x6-initramfs-recovery.itb` rồi giữ nút RESET khi cắm điện. Kiểm tra đang ở recovery: `grep -c overlay /proc/mounts` ra `0`.

**Bước 2 — mở khoá ghi, tháo UBI:**
```bash
insmod mtd-rw i_want_a_brick=1
ubidetach -p /dev/mtd4
```

**Bước 3 — ghi lại toàn bộ vùng UBI gốc (122,5 MB).** Stream từ PC, không chép vào `/tmp` (RAM 256 MB, tmpfs chỉ ~110 MB). Trên PC (Git Bash/WSL), đứng trong thư mục backup:
```bash
cat stock-ubi-region-0x580000-end.bin | ssh root@192.168.1.1 "mtd write - ubi"
ssh root@192.168.1.1 "sha256sum /dev/mtd4"        # so với SHA256SUMS.txt
```

**Bước 4 — env gốc:**
```bash
scp -O mtd2_u-boot-env.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "mtd write /tmp/mtd2_u-boot-env.bin /dev/mtd1"
```

**Bước 5 — FIP gốc** (sau bước này U-Boot OpenWrt không còn):
```bash
scp -O mtd4_FIP.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "mtd write /tmp/mtd4_FIP.bin FIP && sha256sum /dev/mtd3"
```

**Bước 6 — BL2 gốc:** chỉ khi trước đó đã thay BL2 (hướng dẫn cài **không** thay BL2).
```bash
scp -O mtd1_BL2.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "mtd write /tmp/mtd1_BL2.bin BL2 && sha256sum /dev/mtd0"
```

**Bước 7 — Factory: không ghi.** OpenWrt không đụng tới nó. Chỉ ghi lại `mtd3_Factory.bin` khi chắc chắn nó hỏng, và chỉ cho đúng máy này.

**Bước 8 — `reboot -f`.** U-Boot gốc (NMBM, forced-create) dựng lại bảng NMBM; firmware Viettel boot slot `bootflag=2`. Lần đầu có thể lâu hơn bình thường.

## 4. Brick hoàn toàn

Không vào được U-Boot: dùng USB-TTL 3,3 V + `mtk_uartboot` nạp U-Boot vào RAM (xem mục *Cứu máy khi brick* trong [README-viettel-32x6.md](README-viettel-32x6.md)), rồi làm lại từ bước 1. Máy nạp SPI-NAND (CH341A) cũng được, nhưng file dump không có OOB/ECC nên phần mềm nạp phải tự sinh ECC.
