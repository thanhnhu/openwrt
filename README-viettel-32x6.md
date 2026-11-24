# Viettel vAP-32X6V1 — OpenWrt 25.12 (bản build riêng, Multi Firmware)

Nhánh `viettel-32x6/25.12` (tách từ `openwrt-25.12`). Muốn chạy thêm KeeneticOS thì dùng nhánh `viettel-32x6/25.12-multifw` (layout khác, UBI nhỏ hơn). Backup flash gốc và cách quay về firmware Viettel: [README-viettel-32x6-restore.md](README-viettel-32x6-restore.md).

> Đã chạy trên máy thật: cài từ firmware Viettel, recovery, nâng cấp có bản dự phòng, rollback, Multi Firmware (OpenWrt ↔ ImmortalWrt). Phần chưa thử xem mục cuối.

---

## 1. Phần cứng (đã đối chiếu với firmware gốc đang chạy)

| Thành phần | Giá trị | Nguồn |
|---|---|---|
| SoC | MT7981B, 2 nhân A53 | `/proc/cpuinfo`, DTB gốc |
| RAM | 256 MB (~220 MB khả dụng) | `free` trên firmware gốc |
| Flash | SPI-NAND 128 MB, page 2048, block 128 KB, 0 bad block — có nhiều loại chip, xem [Chip NAND](#chip-nand-winbond-gv--kv-hay-macronix) | `/proc/mtd`, sysfs |
| Switch | MT7531, CPU port 6 (2.5G) | DTB gốc (`gsw@0`) |
| Cổng mạng | **1 WAN + 2 LAN** (switch port 0 / 1 / 2), **không có USB** | `board.json`, VLAN gốc `0 1 2 6` |
| Nút | Reset = GPIO1, Mesh/WPS = GPIO0 | DTB gốc |
| LED | **1 đèn RGB**: đỏ GPIO5, xanh dương GPIO7, xanh lá GPIO8 (kích mức thấp). GPIO9 (mức cao) và GPIO34 (mức thấp) cũng làm sáng xanh lá → giữ tắt. GPIO35 không có đèn | test bật từng chân trên máy thật, 2026-11-15 |
| MAC | WAN = Factory `0x24` (`…:57`), LAN = Factory `0x2a` (`…:56`), WiFi tính từ `0x4` | Factory dump + `board.json` gốc |
| WiFi | MT7976 (AX3000), EEPROM ở Factory `0x0` | — |

### Chip NAND: Winbond GV / KV hay Macronix?

Các lô 32x6 dùng các chip SPI-NAND 1 Gbit khác nhau. Phân biệt được, kể cả khi đang chạy firmware gốc:

| Chip | JEDEC ID | OOB | ECC | `oobsize` / `ecc_strength` (sysfs) |
|---|---|---|---|---|
| Winbond **W25N01GV** | `ef aa 21` | 64 B | 1 bit/512 B | `64` / `1` |
| Winbond **W25N01KV** | `ef ae 21` | 96 B | 4 bit/512 B | `96` / `4` |
| Macronix **MX35LF1GE4AB** | `c2 12` | 64 B | 4 bit/512 B | `64` / `4` |

Cách kiểm tra:

- **Firmware gốc Viettel (SSH):** không đáng tin cho việc này (xem ghi chú bên dưới). Chuỗi `W25N01GV`, `MX35LF1GE4AB`, `MT29F2G01ABAGD` tìm thấy trong BL2 chỉ là bảng chip BL2 hỗ trợ, không phải chip trên máy.
  Log kernel gốc cũng bị driver WiFi đẩy trôi mất dòng nhận chip.
- **OpenWrt / recovery:** `dmesg | grep -i "spi nand"` → in thẳng tên hãng và OOB size.
- **U-Boot (UART):** dòng nhận SPI-NAND lúc khởi động.
- **Nhìn chip:** IC 8 chân cạnh SoC, ký hiệu `W25N01GV…`, `W25N01KV…` hoặc `MX35LF1GE4AB…`.

Máy `24:0b:2a:e8:1d:57` (máy đã backup) báo trong `dmesg` của OpenWrt: `Winbond SPI NAND was found ... OOB size: 96`, ECC 4 bit → **Winbond W25N01KV**. (Trước khi flash mình từng suy ra Macronix từ thông số `64`/`4` đọc trên firmware gốc; suy luận đó **sai**: cùng chip nhưng firmware gốc báo `oobsize=64`, kernel mới báo `96`. Nhiều khả năng driver SDK của MediaTek khai báo OOB khác (chưa xác minh), nên cột "sysfs" ở bảng trên chỉ đáng tin khi đọc từ OpenWrt/kernel mới, **không đọc trên firmware Viettel gốc**.)

Hỗ trợ:

- BL2 gốc có bảng chip W25N01GV / MX35LF1GE4AB / MT29F2G01ABAGD, và đọc parameter page với chip lạ.
- U-Boot và kernel trong bản build này có driver cho cả GV, KV và Macronix.
- Vì hướng dẫn **giữ BL2 gốc**, cả ba loại cài như nhau. Chỉ khi thay BL2 (menu 7) mới cần chắc BL2 mới hỗ trợ đúng chip.

### Cổng mạng

Thứ tự jack vật lý ↔ switch port (**đã xác minh** 2026-11-15 bằng cách cắm cáp lần lượt và đọc thanh ghi PMSR của MT7531): jack **WAN** = port 0 → `wan`, jack **LAN1** = port 1 → `lan1`, jack **LAN2** = port 2 → `lan2`.

---

## 2. File firmware sau khi build

Trong `~/owrt-32x6/bin/targets/mediatek/filogic/` (WSL):

| File | Dùng để |
|---|---|
| `openwrt-mediatek-filogic-viettel_32x6-bl31-uboot.fip` | U-Boot (ghi vào FIP `0x380000`) |
| `openwrt-mediatek-filogic-viettel_32x6-preloader.bin` | BL2 — **không cần thay**, giữ BL2 gốc |
| `openwrt-mediatek-filogic-viettel_32x6-initramfs-recovery.itb` | Recovery chạy trong RAM (TFTP) |
| `openwrt-mediatek-filogic-viettel_32x6-squashfs-sysupgrade.itb` | Firmware chính |

Bộ file **dùng được cho mọi máy 32x6**: không chứa Factory, MAC và hiệu chuẩn WiFi luôn đọc từ phân vùng Factory của chính máy đó.

---

## 3. Layout flash

```
0x0000000  BL2        1 MB   (giữ nguyên BL2 gốc)
0x0100000  u-boot-env 512 KB (env gốc, OpenWrt không dùng)
0x0180000  Factory    2 MB   (MAC + calib WiFi — KHÔNG BAO GIỜ ghi đè)
0x0380000  FIP        2 MB   (U-Boot OpenWrt)
0x0580000  ubi        122.5 MB (~121 MB dùng được), gồm các volume:
             ubootenv, ubootenv2          env U-Boot (Linux đọc/ghi bằng fw_printenv/fw_setenv)
             fit       + rootfs_data      slot 1: firmware đang chạy
             fit_2     + rootfs_data_2    slot 2
             fit_spare + rootfs_data_spare slot Dự phòng (OpenWrt trước lần nâng cấp gần nhất)
             recovery                     initramfs recovery (khẩn cấp)
```

**Chia chỗ cho cấu hình và gói cài thêm (`rootfs_data*`):**
- **Slot 2** tối đa **16 MB** (`rootfs_data_max=0x1000000`), do U-Boot hoặc sysupgrade của chính firmware đó tạo.
- **Dự phòng** chỉ có một vùng 3 MB chứa bản sao lưu cấu hình của OpenWrt cũ.
- **OpenWrt ở slot 1 lấy hết phần còn lại**, sau mỗi lần nâng cấp. Nếu slot 2 đang trống thì vẫn chừa sẵn chỗ cho nó (30 MB ảnh + 16 MB cấu hình), để sau này nạp được mà không phải thu nhỏ OpenWrt.

Ví dụ: env 2 MB + recovery 10 MB + ImmortalWrt 28,5 MB và cấu hình 16 MB ở slot 2 + OpenWrt 12 MB + Dự phòng 12 MB và 3 MB + 2 MB dư → OpenWrt có khoảng **35 MB** cho cấu hình và gói.

UBIFS không đổi kích thước tại chỗ được, nên kích thước mới chỉ có hiệu lực khi vùng cấu hình được tạo lại. OpenWrt thì tạo lại ở lần nâng cấp tới (cấu hình được giữ). Firmware ở slot 2 thì phải `multifw reset 2`, tức **xoá cấu hình của firmware đó**; sao lưu trước nếu cần. Cài OpenWrt qua menu U-Boot mục 4 thì lần đầu chỉ có 16 MB; nâng cấp một lần là lấy hết chỗ.

---

## 4. Cài lần đầu từ firmware Viettel

Cần: SSH vào firmware gốc (đã làm, xem `Why/OpenWRT/vAP-32X6V1 (netis-NX31)/Readme.txt`), **Tftpd64** trên PC, cáp mạng.

1. **Backup** — đã có trong `Why/OpenWRT/vAP-32X6V1 (netis-NX31)/Backup-32x6-240b2ae81d57-2026-11-15`. Máy khác thì dump lại trước (cách làm trong [README-viettel-32x6-restore.md](README-viettel-32x6-restore.md)).
2. Chép U-Boot lên router (firmware gốc ở 192.168.2.1 hoặc 192.168.1.1):
   ```bash
   scp -O openwrt-mediatek-filogic-viettel_32x6-bl31-uboot.fip root@192.168.2.1:/tmp/
   ssh root@192.168.2.1
   sha256sum /tmp/*.fip            # so với sha256sums của bản build
   mtd write /tmp/openwrt-mediatek-filogic-viettel_32x6-bl31-uboot.fip FIP
   dd if=/dev/mtd4 bs=1 count=$(wc -c < /tmp/*.fip) | sha256sum   # phải trùng
   ```
   Chỉ ghi **FIP**. Lý do: phân vùng BL2 trong DT gốc có cờ read-only, và BL2 gốc (TF-A của MTK SDK) đọc FIP chuẩn TF-A tại `0x380000`. *(Việc BL2 gốc nạp FIP OpenWrt chưa xác minh trên chính máy này — nên chuẩn bị sẵn USB-TTL.)*
3. PC đặt IP tĩnh **192.168.1.254/24**, chạy Tftpd64 trỏ vào thư mục có `…-initramfs-recovery.itb`. Cắm cáp vào cổng **LAN**.
4. Trên router: `reboot`. U-Boot mới chạy `_firstboot`: thấy UBI gốc không hợp lệ → **xoá vùng ubi** (đã backup) → tạo env → không có firmware → tự tải `initramfs-recovery.itb` qua TFTP và boot.
5. Vào `http://192.168.1.1` (root, không mật khẩu) → *System → Backup / Flash Firmware* → flash `…-squashfs-sysupgrade.itb`, **bỏ chọn "Keep settings"**.
6. (Khuyến nghị) giữ một bản recovery trong NAND:
   ```bash
   scp -O openwrt-…-initramfs-recovery.itb root@192.168.1.1:/tmp/
   ssh root@192.168.1.1 multifw flash-recovery /tmp/openwrt-…-initramfs-recovery.itb
   ```

Rủi ro duy nhất là bước 2: nếu FIP mới không chạy, phải cứu bằng USB-TTL + `mtk_uartboot`. Xem mục 9.

---

## 5. Multi Firmware (Đa firmware)

Máy giữ được nhiều firmware cùng lúc, mỗi firmware có cấu hình riêng:

| Slot | Volume | Dùng để |
|---|---|---|
| **1 — Đang chạy** | `fit` + `rootfs_data` | firmware đang boot |
| **2** | `fit_2` (+ `rootfs_data_2`) | firmware khác (ImmortalWrt, bản OpenWrt khác…) |
| **Dự phòng** (spare) | `fit_spare` + `rootfs_data_spare` | OpenWrt trước lần nâng cấp gần nhất, để quay lại |
| **Recovery** | `recovery` | khi mọi slot đều hỏng |

Kernel và fstools chỉ boot volume tên `fit`/`rootfs_data`, nên **đổi firmware = đổi tên volume**: slot muốn chạy lấy tên `fit`, firmware đang chạy lấy tên slot đó. Từ Linux, việc đổi tên làm bằng **một** lệnh `ubirename` (nguyên tử) rồi reboot. Tên hiển thị của firmware gắn theo ID volume (`fwname_<id>` trong env U-Boot), nên không lệch khi đổi slot.

**Nâng cấp** (luôn có bản dự phòng): khi sysupgrade firmware đang chạy (LuCI hoặc `sysupgrade`):
- Firmware đang chạy chuyển vào slot **Dự phòng** (thay bản dự phòng cũ), kèm **bản sao lưu cấu hình** (`sysupgrade -b`) trong vùng 3 MB. Vùng cấu hình cũ bị xoá để OpenWrt mới lấy chỗ, nên khi quay về bản dự phòng thì cấu hình còn, **gói đã cài thì mất**. **Slot 2 không bị đụng tới.**
- Bản mới ghi vào slot 1, vùng cấu hình mới lấy hết chỗ trống (xem mục 3), U-Boot bật chế độ *chạy thử*: mỗi lần boot tăng `boot_count`; chạy ổn ~60 s thì `/etc/init.d/multifw` xác nhận.
- Không boot được 3 lần → **tự quay về bản dự phòng** (kernel panic tự reboot sau 1 s; treo cứng thì rút/cắm điện 3 lần). LuCI báo "rolled back".
- Trước khi ghi, sysupgrade **kiểm tra dung lượng**; thiếu chỗ cho bản dự phòng thì từ chối và gợi ý xoá slot 2 (`multifw delete 2`) hoặc xoá cấu hình của nó (`multifw reset 2`).

**Thay firmware ở slot 2** (`multifw flash 2`, hoặc nút *Thay…* trên LuCI): ghi đè tại chỗ, bản cũ ở slot 2 và cấu hình của nó bị xoá. Dự phòng chỉ giữ OpenWrt cũ; `multifw restore 2` chuyển bản Dự phòng vào slot 2.

**Lệnh `multifw`:**

| Lệnh | Tác dụng |
|---|---|
| `multifw status` | trạng thái các slot (JSON) |
| `multifw boot 2\|spare` | chạy firmware ở slot đó (reboot ngay) |
| `multifw flash 2 <file.itb> [--name TÊN]` | nạp firmware vào slot 2 (thay bản cũ) |
| `multifw restore 2` | chuyển bản Dự phòng vào slot 2 |
| `multifw delete 2\|spare` / `multifw reset 2\|spare` | xoá slot / xoá cấu hình của slot |
| `multifw name <slot> <tên>` | đổi tên hiển thị |
| `multifw flash-recovery <file.itb>` | ghi recovery vào NAND |

Mọi cách đổi firmware đều là **đổi chỗ** slot 1 với slot được chọn: firmware vừa chạy chuyển vào slot đó. Đi bằng slot nào thì quay về bằng slot đó. **Nút Mesh luôn boot OpenWrt**, dù OpenWrt đang nằm ở slot nào: env `mfw_home` ghi slot đang chứa OpenWrt, được cập nhật mỗi lần đổi slot (cả từ Linux lẫn U-Boot), và OpenWrt tự đặt lại `mfw_home=1` mỗi lần khởi động. Đang chạy OpenWrt thì nút không làm gì.

**Đổi firmware**, có 4 cách:

| Cách | Cần gì |
|---|---|
| LuCI *Advanced → Đa firmware → Khởi động* | trình duyệt |
| `multifw boot 2` (từ OpenWrt) hoặc `fw_setenv boot_slot 2 && reboot` (từ **bất kỳ** firmware nào, kể cả ImmortalWrt) | SSH |
| **Giữ nút Mesh/WPS khi cắm điện**, nhả khi **đèn xanh dương** sáng (~3 s) → luôn boot OpenWrt | không cần gì |
| Menu U-Boot mục 9/10 | USB-TTL |

**ImmortalWrt ở slot 2** (bản build sẵn của fork `quytttb/immortalwrt-mt798x-rebase` v2.5.0, đã tải và kiểm sha256 tại `Why/OpenWRT/vAP-32X6V1 (netis-NX31)/ImmortalWrt-v2.5.0`): LuCI *Advanced → Đa firmware → Slot 2 → Nạp…*, hoặc

```bash
scp -O immortalwrt-mediatek-filogic-viettel_32x6-squashfs-sysupgrade.itb root@192.168.1.1:/tmp/
ssh root@192.168.1.1 multifw flash 2 /tmp/immortalwrt-mediatek-filogic-viettel_32x6-squashfs-sysupgrade.itb --name "ImmortalWrt 2.5.0"
ssh root@192.168.1.1 multifw boot 2
```

Từ ImmortalWrt quay về: `ssh root@<IP> 'fw_setenv boot_slot 2 && reboot'` (OpenWrt lúc đó nằm ở slot 2). ImmortalWrt của fork đọc/ghi đúng env U-Boot này (cùng volume `ubootenv`, kích thước `0x1f000`).

Lưu ý:
- ImmortalWrt không có `multifw`: nó không xác nhận chạy thử, và sysupgrade của chính nó ghi đè slot 1 không sao lưu. Đừng cài ImmortalWrt bằng sysupgrade từ OpenWrt (sẽ bị coi là bản chạy thử và tự quay về sau 3 lần boot); dùng `multifw flash`.
- Bản ImmortalWrt đó không giữ GPIO9/34 ở trạng thái tắt nên đèn xanh lá có thể sáng lẫn màu.
- Không còn firmware nào khác trong máy (ví dụ đã ghi đè slot 1 bằng TFTP menu 4) thì không đổi được; flash lại bằng menu 4 hoặc boot recovery rồi sysupgrade.

**Bài học khi sửa script:** không viết `printf ... "$(fw_printenv ...)" | fw_setenv -s -`. `fw_setenv` giữ khoá `fw_printenv.lock` rồi chờ đọc đường ống, trong khi `fw_printenv` ở vế trái chờ đúng khoá đó: sysupgrade bị **khoá chết** (đèn xanh dương nháy mãi, không SSH được). Luôn đọc biến trước rồi ghi qua file (`fw_setenv -s file`). Nếu máy treo kiểu này: rút điện, cắm lại; U-Boot vào recovery, đổi tên volume về (`ubirename /dev/ubi0 fit_spare fit rootfs_data_spare rootfs_data`) rồi reboot.

**KeeneticOS không đặt vào slot được**: kernel 4.9 và `ndm` (đóng mã) cần phân vùng MTD thô riêng, không boot từ volume UBI `fit`. Nhánh `viettel-32x6/25.12-multifw` chừa 32 MB cuối NAND cho KeeneticOS (UBI còn 90,5 MB) và cài nó song song (`keenetic-32x6/README.md`).

**Từ bản build có slot 3:** bản này không còn slot 3. Trước khi nâng cấp, chạy `multifw delete 3` trên bản cũ (lấy lại firmware cần giữ trước). Đã nâng cấp rồi thì xoá bằng `ubirmvol /dev/ubi0 -N fit_3` và `ubirmvol /dev/ubi0 -N rootfs_data_3`. Lệnh `multifw backup` cũng đã bỏ: nâng cấp luôn giữ bản dự phòng, và env `upgrade_backup` cũ được xoá ở lần khởi động đầu tiên.

**Từ nhánh `-multifw` (có KeeneticOS) về nhánh này:**
1. Trên OpenWrt đang chạy:
   - xoá slot 2 (bản ImmortalWrt build cho UBI 90,5 MB không chạy được trên UBI lớn hơn);
   - xoá volume `kn_log`;
   - ghi FIP của nhánh này (`insmod mtd-rw i_want_a_brick=1`, rồi `mtd write … FIP`);
   - sysupgrade giữ cấu hình.
2. UBI tự lớn lên 122,5 MB và chiếm luôn vùng KeeneticOS: **KeeneticOS mất**, còn U-Config ở `0x100000` thì không bị đụng.
3. Xoá bản Dự phòng (OpenWrt của layout cũ), rồi nạp ImmortalWrt v2.5.0 gốc vào slot 2.
4. Nâng cấp thêm một lần để OpenWrt lấy hết chỗ.

---

## 6. Menu U-Boot (qua UART 115200 8N1)

| # | Mục |
|---|---|
| 0 | Run default boot command |
| 1 | Boot system via TFTP (`…-initramfs-recovery.itb`) |
| 2 | Boot production system from NAND |
| 3 | Boot recovery system from NAND |
| 4 | Load production system via TFTP then write to NAND (`…-squashfs-sysupgrade.itb`) |
| 5 | Load recovery system via TFTP then write to NAND |
| 6 | Load BL31+U-Boot FIP via TFTP then write to NAND |
| 7 | Load BL2 preloader via TFTP then write to NAND (**rủi ro cao**) |
| 8 | Multi Firmware: load slot 2 via TFTP (`slot2.itb`) |
| 9 | Multi Firmware: boot slot 2 |
| 10 | Multi Firmware: boot spare (OpenWrt trước lần nâng cấp gần nhất) |
| 11 | Reboot |
| 12 | Reset all settings to factory defaults |

Không cần UART:
- **Giữ RESET khi cắm điện**: boot recovery qua TFTP, server 192.168.1.254.
- **Giữ MESH khi cắm điện**, nhả khi đèn xanh dương sáng (~3 s): boot OpenWrt. Giữ lâu hơn cũng được: U-Boot chờ tới khi nhả (tối đa 30 s, đèn xanh dương tắt) rồi mới boot, nên OpenWrt không vô tình vào failsafe.

---

## 7. Trang LuCI "Advanced" (Nâng cao)

Menu **Advanced** (tiếng Việt: **Nâng cao**) là một mục riêng ở thanh menu trên cùng, cùng cấp với Status/System/Network và nằm ngay bên trái *Log out*. Gồm các phần:

**Từng radio:**
- Mã quốc gia.
- Công suất phát: để trống = mức tối đa luật cho phép.
- Độ rộng kênh, cell density.
- Beamforming SU/MU.
- Khoảng cách (ACK timeout).
- Force 40 MHz.

**Từng AP:**
- Không ngắt client yếu (`disassoc_low_ack`).
- 802.11k/v.
- Cách ly client.

**Hai preset và Đa firmware:**
- Preset **"Through-wall"** (xuyên tường):
  - công suất tối đa hợp lệ;
  - 2.4 GHz 20 MHz;
  - cho phép basic rate thấp;
  - bật beamforming;
  - không ngắt client yếu.
- Preset **"Balanced"** đưa các tuỳ chọn trên về mặc định.
- Phần **Đa firmware** (Multi Firmware): bảng các slot (Đang chạy / 2 / Dự phòng / Recovery) với nút *Khởi động*, *Nạp…/Thay…*, *Đổi tên*, *Xóa*.
- **Ngôn ngữ** đổi ở *System → System → Language and Style → Language* (Auto / English / Tiếng Việt), áp dụng cho toàn bộ LuCI.

**Trang Tổng quan (Status → Overview)** có thêm mục **Hardware**: nhiệt độ CPU (đổi màu từ 70 °C, đỏ từ 85 °C) và kiểu NAND (hãng, dung lượng, OOB, ECC; tên chip dạng "≈ W25N01KV" là suy ra từ hãng + OOB, không đọc từ ID chip).

Ngôn ngữ: giao diện LuCI có sẵn tiếng Việt cho các gói chính (base, firewall, package-manager, sqm) và trang Advanced có bản dịch riêng trong [po/vi](package/luci-app-advanced/po/vi/advanced.po).

Công suất phát luôn bị giới hạn bởi mã quốc gia và dữ liệu hiệu chuẩn. "Xuyên tường" không vượt được giới hạn phần cứng hay luật.

Gói có trong bản build:
- LuCI tiếng Việt, HTTPS.
- SQM (`luci-app-sqm`).
- WireGuard (`luci-proto-wireguard`).
- Mesh 802.11s + WPA3 (`wpad-mesh-mbedtls`).
- `multi-firmware` (lệnh `multifw`), `luci-app-advanced`, `kmod-mtd-rw`, `iperf3`, `ethtool`.

---

## 8. Build (WSL Debian)

```bash
# một lần: cài công cụ build
sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev python3-dev \
  python3-setuptools rsync swig unzip zlib1g-dev file wget zstd

# chạy trong WSL, đứng ở thư mục repo OpenWRT
# build toàn bộ: sync mã nguồn (nhánh + thay đổi chưa commit) vào ~/owrt-32x6 (ext4),
# feeds, áp viettel-32x6.diffconfig, download, make. Log: ~/owrt-32x6/build-32x6.log
bash viettel-32x6-build.sh
```

Các bước thủ công tương đương:

```bash
bash viettel-32x6-sync-wsl.sh          # từ thư mục repo
cd ~/owrt-32x6
./scripts/feeds update -a && ./scripts/feeds install -a
cp viettel-32x6.diffconfig .config && make defconfig
make download -j16 && make -j$(nproc)
```

Không build trực tiếp trên ổ `D:` vì NTFS không phân biệt hoa/thường và rất chậm.

File liên quan trong repo: [viettel-32x6.diffconfig](viettel-32x6.diffconfig) (danh sách gói), [viettel-32x6-build.sh](viettel-32x6-build.sh), [viettel-32x6-sync-wsl.sh](viettel-32x6-sync-wsl.sh), [viettel-32x6-genuboot.py](viettel-32x6-genuboot.py) (sinh patch U-Boot), [viettel-32x6-readme-copy.py](viettel-32x6-readme-copy.py) (chép README này sang thư mục thiết bị).

### Build trên GitHub Actions

Workflow [build-viettel-32x6.yml](.github/workflows/build-viettel-32x6.yml) **chỉ chạy khi bấm tay**: trên GitHub vào *Actions → Build Viettel 32x6 firmware → Run workflow*, chọn nhánh `viettel-32x6/25.12` hoặc `viettel-32x6/25.12-multifw`.

- Kết quả: artifact gồm các file firmware + `config.buildinfo` + `sha256sums`.
- Nếu để bật `publish` (mặc định) thì tạo thêm release kèm các file đó. Tag là bản OpenWrt chính thức mà nhánh dựa
  trên, tự tìm theo upstream, có tiền tố `32x6` để không trùng tag của upstream (vd. `32x6v25.12.6`), thêm
  `-multifw` cho nhánh `*-multifw`. Build lại cùng phiên bản thì release cũ bị thay và tag chuyển sang commit mới.
- Phiên bản ghi trong firmware là `CONFIG_VERSION_NUMBER` trong `viettel-32x6.diffconfig` (kho gói `apk` theo
  `CONFIG_VERSION_REPO`). Workflow dừng nếu số này khác bản upstream của nhánh: khi rebase lên bản mới thì sửa cả hai.
- Mất khoảng 2–2,5 giờ. Thư mục `dl/` được cache cho các lần sau.

Mọi workflow CI của upstream đã được chuyển sang [.github/workflows-disabled/](.github/workflows-disabled/) nên không tự chạy trong fork. Muốn bật lại cái nào thì chuyển file đó về `.github/workflows/`.

Nếu build U-Boot báo `syntax error near unexpected token '('`: PATH của Windows (có `Program Files (x86)`) bị WSL nối vào. Script build đã đặt PATH chỉ gồm thư mục Linux; khi build tay thì chạy `export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` trước.

Nếu `make download` báo `unable to resolve host address`: DNS proxy của WSL (`10.255.255.254`) quá chậm so với timeout 5 s của script tải. Đặt `/etc/resolv.conf` thành `nameserver 1.1.1.1` / `nameserver 8.8.8.8` rồi khoá lại bằng `sudo chattr +i /etc/resolv.conf`. Script build tự kiểm tra DNS trước khi chạy.

---

## 9. Cứu máy khi brick

- **Còn vào được U-Boot:**
  - giữ RESET khi cắm điện → TFTP recovery;
  - hoặc dùng UART menu 4/5/6.
- **U-Boot hỏng (FIP lỗi):**
  1. Dùng USB-TTL 3.3 V (TX/RX/GND trên board) + `mtk_uartboot` với BL2 RAM payload để nạp U-Boot vào RAM, không ghi NAND. File `bl2-viettel-32x6-ram.bin` lấy từ release `quytttb/bl-mt798x-dhcpd`. Xem `ImmortalWRT/docs/huong-dan-nap-firmware.md`.
  2. Sau đó ghi lại FIP bằng menu 6.
- **Về hẳn firmware Viettel:** làm theo [README-viettel-32x6-restore.md](README-viettel-32x6-restore.md).

---

## 10. Đã kiểm chứng / chưa kiểm chứng

Đã chạy trên máy thật:
- [x] Jack vật lý ↔ `wan`/`lan1`/`lan2` (port 0/1/2); MAC `wan` = `…:57`, LAN = `…:56`.
- [x] LED: đỏ khi boot/failsafe, xanh dương khi nâng cấp (và khi U-Boot nhận nút Mesh), xanh lá khi chạy.
- [x] Chip NAND: Winbond W25N01KV (OOB 96, ECC 4 bit).
- [x] Cài từ firmware Viettel: BL2 gốc nạp FIP mới, `_firstboot` format UBI, recovery qua TFTP, sysupgrade vào NAND.
- [x] Multi Firmware: `multifw boot`, `fw_setenv boot_slot` (từ ImmortalWrt), nút Mesh về OpenWrt, nâng cấp giữ bản cũ ở Dự phòng (slot 2 không bị đụng), kiểm tra dung lượng, rollback về Dự phòng (giả lập 3 lần boot lỗi), `flash`/`delete` slot 2.
- [x] Chia chỗ: sau một lần nâng cấp, OpenWrt có `rootfs_data` 31,8 MB, Dự phòng 3 MB chứa `sysupgrade.tgz`, ImmortalWrt v2.5.0 ở slot 2 được 16 MB. Rollback giả lập boot bản Dự phòng với cấu hình được khôi phục. `multifw boot 2` và `fw_setenv boot_slot 2` qua lại hai bên đều được.
- [x] Chuyển từ layout `-multifw` (UBI 90,5 MB) sang layout này: ghi FIP, rồi sysupgrade. UBI tự lớn lên 122,5 MB, không cần format, và các volume được giữ.

Chưa thử:
- [ ] `multifw restore`, các nút trên trang LuCI *Advanced* bằng mắt.
- [ ] Rollback với một ảnh lỗi thật (mới giả lập bằng `boot_count`).
- [ ] Máy dùng chip W25N01GV hoặc Macronix.
- [ ] Kernel in `u-boot-env-layout ... Invalid calculated CRC32 ... error -22` cho `ubootenv`/`ubootenv2`; `fw_printenv`/`fw_setenv` vẫn đúng, có vẻ vô hại, chưa tìm nguyên nhân.
