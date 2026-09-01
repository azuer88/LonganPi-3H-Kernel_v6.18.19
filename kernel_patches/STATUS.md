# kernel_patches Patch Application Status
## Target kernel: 6.18.48 (at /extra/LPI3H/LonganPi-3H-SDK/build/linux)
## Applied on: 2026-03-25 | Last updated: 2026-09-01

## Kernel base upgrade: 6.18.19 -> 6.18.48 (2026-09-01)
All 69 commits (67 numbered patches + 0068/0069 below) rebased cleanly from
`v6.18.19` (4aea1dc4c) onto `v6.18.48` (2e57d67d6) with zero conflicts —
`git rebase --onto v6.18.48 v6.18.19 HEAD` in a shallow clone. Clean-built and
boot-tested on lpi3h-f182: WiFi, HDMI display, HDMI audio, Panfrost GPU
(glmark2 score 131, matches 6.18.19 baseline), PWM/SPI nodes all verified
working. All history below that refers to "6.18.19 base" predates this
upgrade and is kept for context; the patches themselves did not change,
only their base commit.

---

## Skipped (already upstream in 6.18.19) — NOT in kernel_patches
- 0001 LPI3H DTS, 0003 smccc export, 0004/0007 cpufreq blocklist,
  0005/0008 cpufreq nvmem, 0006/0009 OPP DTS, 0025 DTB Makefile,
  0044 thermal, 0045 DMA, 0051 CH341, 0053 pca9557

## Removed after initial apply
- 0048 ST7789T3 1.9-inch display — removed via `git rebase` (not in linux.working
  either; causes display issues on LPI3H hardware; CONFIG_FB_TFT entries removed
  from defconfig)

---

## Applied (69 commits on top of 6.18.48 base: 2e57d67d6)
All patches applied except 0048. Current HEAD: dc044f74c
(previously 67 commits on 6.18.19 base 4aea1dc4c, HEAD eb924cc03 — see
"Kernel base upgrade" note above)

  829bec518  add lpi3h defconfig                                    ← 0002
  6af6b6e0f  de33 ccu support                                       ← 0010 (fuzz)
  94d20a8f0  dts: allwinner: enable display for lpi3h               ← 0012 (fuzz)
  9c44be7ba  longanpi_3h_defconfig: update for display, debian etc. ← 0013
  090c87a25  longanpi_3h_defconfig: enable devtmpfs                 ← 0014
  7b150b5d4  longanpi_3h_defconfig: enable cgroup & namespace       ← 0015
  8812207c9  drivers: aic8800: import driver from vendor            ← 0016
  2eb4506d3  drivers: aic8800: fix build                            ← 0017 (fuzz)
  2ff547280  drivers: aic8800: change default firmware load path    ← 0018
  6994469a2  drivers: aic8800: enable 5Ghz                         ← 0019
  9b4fb98d4  drivers: aic8800: use UBUNTU config                   ← 0020
  8f195ec07  drivers: aic8800: disable debug log                   ← 0021
  307df3127  longanpi_3h_defconfig: enable tcp cong                ← 0022
  9b1e73296  longanpi_3h_defconfig: enable pktgen                  ← 0023
  b239647b5  longanpi_3h_defconfig: enable usb gadget cdc composite← 0024
  8bd71d8cd  longanpi_3h_defconfig: enable aic8800 wifi support    ← 0026
  b4b12732c  drivers: add aic8800 bluetooth support                ← 0027 (fuzz)
  09defcc8a  longanpi_3h_defconfig: enable aic8800 bluetooth support← 0028
  159491785  drivers: fix aic8800 bluetooth build                  ← 0029
  87b847fba  longanpi_3h_defconfig: add some usb gadgets configs   ← 0030
  a1688a128  longanpi_3h_defconfig: enable gpio sysfs interface    ← 0031
  4302d4d42  drivers: aic8800: update vendor drivers to 20231212   ← 0032
  9306468d6  drivers: aic8800: fix build for 20231212 vendor driver← 0033
  1d7b0ef4c  longanpi_3h_defconfig: enable CONFIG_GPIO_CDEV_V1     ← 0034
  a8f3d00d2  longanpi_3h_defconfig: enable some configs for docker ← 0035
  00de508f9  longanpi_3h_defconfig: enable TUN as kernel module    ← 0036
  066a3bce9  longanpi_3h_defconfig: enable some feature for lpi3h  ← 0037
  ea0a03222  longanpi_3h_defconfig: enable more initramfs formats  ← 0038
  63592cb46  longanpi-3h: default enable uart1 & i2c3              ← 0039 (fuzz)
  0e96c5d0f  arch: arm64: configs: longanpi_3h_defconfig: clean    ← 0040
  32199b200  add-ac300-ephy-support-for-linux                      ← 0041 (fuzz)
  5fd519bfe  sun50i-h618-fix-emac1-mdio1                           ← 0042 (fuzz)
  9ac6b3d09  linux: fix some incorrect nodes                       ← 0043 (manual*)
  ef34c7b51  linux: add allwinner bsp support                      ← 0046 (manual**)
  30bd15c1a  linux: fix H618 emac1                                 ← 0047 (manual***)
  8f6318d76  [linux] Add HID wakeup support                        ← 0049 (fuzz)
  7cedfae9d  add pwm and fan support                               ← 0050 (fuzz)
  b495ca090  cdrom support images larger than 2.2GB                ← 0052
  857f1afb4  add cgroup CPUACCT and cfs bandwidth                  ← 0054
  c0b84baf1  dts: fix sun50i-h618-longanpi-3h syntax errors        ← build fix
  66ba590d6  dts: remove duplicate vendor iommu and ve nodes       ← build fix
  599a3f15e  build: fix API compatibility for 6.18 kernel          ← build fix
  3e5d2ec71  build: fix more 6.18 API compatibility                ← build fix
  97aa75f24  build: fix aic8800 rwnx_main.c API compat for 6.18   ← build fix
  ddbc50278  build: add cfg80211_cac_event link_id compat          ← build fix
  8b4f9633a  build: fix MODULE_IMPORT_NS string syntax in aic_btusb← build fix
  a0dc0f272  build: fix pwm-sunxi-enhance for 6.18 pwm_chip API   ← build fix
  daf080d2a  aic8800: suppress CAUTION regulatory log message      ← 0049
  bc1ba6f12  cedrus: add H616/H618 VPU support with SRAM C1       ← 0050
  3c90865b8  cedrus: reduce watchdog polling interval to 5ms       ← 0051
  b761887ef  cedrus: reduce watchdog to 0ms (immediate work queue) ← 0052
  882f27c40  cedrus: watchdog back to 5ms (best practical HZ=100)  ← 0053
  888837b51  cedrus/dts: fix H616 VE interrupt GIC SPI 89→93      ← 0054
  dccc300f5  dts: constrain CMA pool below 4 GB (sun4i DMA32)     ← 0055
  887285633  defconfig: add HDMI I2S audio drivers                 ← 0056
  e89002e43  sound/dts: add AHUB driver for HDMI audio            ← 0057
  930f33032  defconfig: add CONFIG_SND_SIMPLE_CARD=m              ← 0058
  79af3c50a  defconfig: enable USB_SERIAL + USB_SERIAL_CH341     ← 0059
  5183590ea  defconfig: enable WATCHDOG_HANDLE_BOOT_ENABLED       ← 0060
  8c1dac540  dts: enable LED1 (PG4, active-low)                   ← 0061
  09a8d4145  dts: add spidev node on SPI1 (PH5-PH8 header)       ← 0062
  e1fed238c  aic8800_fdrv: fix use-after-free in rxframes         ← 0063
  5da372d71  pwm: sunxi-enhance: port to pwmchip_alloc() API      ← 0064
  0772c03bc  pwm: sunxi-enhance: propagate DT node to pwm_chip    ← 0065
  4a13c2ea2  aic_load_fw: fix FORTIFY_SOURCE false positive        ← 0066
  c736155c6  aic_load_fw: return -ENODEV instead of -1            ← 0067
  18cd3c0b4  defconfig: xt_MASQUERADE/xt_NAT for Docker; BT fix   ← 0068
  dc044f74c  aic8800_fdrv: rate-limit rxq overflow; MAX_RXQLEN=4096 ← 0069

Manual fix notes:
  *  0043: PG17/PG18 pin order in h616.dtsi; uart1 pinctrl-names in LPI3H DTS
           (i2c0_pins and r_i2c pinctrl already upstream — skipped)
  ** 0046: DTC_INCLUDE moved to scripts/Makefile.dtbs in 6.18 (was Makefile.lib);
           use separate -I flag not space-separated DTC_INCLUDE;
           add bsp/include as -I to both cpp_flags and DTC -i args;
           dma_heap_find() added manually; dma_heap_buffer_alloc signature
           fixed from "static int" to "struct dma_buf *"
 *** 0047: added "struct reg_field syscon_field" and "u32 syscon_idx = 0"
           declarations to sun8i_dwmac_probe (declaration hunk failed)

Build fixes (not in original linux/ patches):
  - sun50i-h618-longanpi-3h.dts: spurious }; between &usbphy and &pwm (from 0050
    fuzz application); &pwm block missing closing }; — both fixed
  - sun50i-h616.dtsi: vendor mmu_aw: iommu@30f0000 (added by 0046) conflicts with
    upstream iommu: iommu@30f0000 — removed vendor node plus dependent ve/ve1 nodes;
    corresponding aliases and overrides removed from LPI3H DTS

---

## Defconfig changes (longanpi_3h_defconfig)
Relative to original linux/ patches:
  - CONFIG_FB_TFT=m removed (no TFT display used; was pulled in by 0048)
  - CONFIG_FB_TFT_ST7789T3=m removed (same reason)
  - CONFIG_FSCACHE=m → CONFIG_FSCACHE=y (FSCACHE is bool in 6.18, not tristate)

---

## PORTED: 0011-sun4i-add-h616-display-support.patch

### Summary
Patch 0011 was written for 6.7-rc3. The 6.18 kernel already has H616/DE33 display
support upstream but with a different API:

  Patch 0011 (6.7 API)          -> 6.18 API
  mixer->cfg->is_de33            -> mixer->cfg->de_type == SUN8I_MIXER_DE33
  adds sun8i_top_regmap_config   -> already at line 417 in mixer.c
  adds sun8i_disp_regmap_config  -> already at line 425 in mixer.c
  adds sun8i_mixer_de2_init()    -> init inlined in mixer_bind (line 455)
  adds sun8i_mixer_de33_init()   -> init inlined in mixer_bind (line 473)
  adds sun8i_blender_regmap()    -> already in mixer.h (line 235)

39 hunks total; partially applied creating duplicates + compile errors. Fully reverted.

### Files modified by 0011
- drivers/gpu/drm/sun4i/sun4i_tcon.c     (all hunks apply cleanly with --fuzz=3)
- drivers/gpu/drm/sun4i/sun4i_tcon.h     (all hunks apply cleanly)
- drivers/gpu/drm/sun4i/sun8i_csc.c      (all hunks apply cleanly)
- drivers/gpu/drm/sun4i/sun8i_hdmi_phy.c (all hunks apply cleanly)
- drivers/gpu/drm/sun4i/sun8i_mixer.c    (6 OK / 5 FAILED — duplicates + is_de33)
- drivers/gpu/drm/sun4i/sun8i_mixer.h    (4 OK / 1 FAILED — blender_regmap dup)
- drivers/gpu/drm/sun4i/sun8i_ui_layer.c (2 OK / 5 FAILED — bld_regs + scaler)
- drivers/gpu/drm/sun4i/sun8i_vi_layer.c (3 OK / 3 FAILED — bld_regs)
- drivers/gpu/drm/sun4i/sun8i_vi_scaler.c (0 OK / 1 FAILED)

### To REVERT all applied patches (back to 6.18.19 base)
  cd /home/ubuntu/Projects/test/LonganPi-3H-SDK/build/linux
  git reset --hard 4aea1dc4c

### What was done
Manual port to 6.18 API. Changes committed as 56dce452b010:
- sun50i-h616.dtsi: added reg-names = "mixer"/"top"/"display" to mixer0 node
  (6.18 driver uses devm_platform_ioremap_resource_byname, requires named regs)
- sun8i_hdmi_phy.c: added H616 MPLL/cur_ctr/phy_config tables, variant struct,
  and OF table entry for allwinner,sun50i-h616-hdmi-phy
- sun4i_tcon.h: added SUN4I_TCON_GCTL_PAD_SEL BIT(1)
- sun4i_tcon.c: set PAD_SEL in sun4i_tcon_bind
- sun8i_csc.c: added sun8i_csc_base(), sun8i_de33_ccsc_set_coefficients(),
  DE33 branch in sun8i_csc_set_ccsc_coefficients(), updated sun8i_csc_enable_ccsc()
Skipped: mixer.c/h, ui_layer.c, vi_layer.c, vi_scaler.c (already upstream in 6.18)

### Verification
Display pipeline confirmed working on device lpi3h-f1a0 (2026-03-27):
  sun4i-drm display-engine: bound 1100000.mixer
  sun4i-drm display-engine: bound 6515000.lcd-controller
  sun8i-dw-hdmi: Detected HDMI TX controller v2.12a
  sun4i-drm: Initialized sun4i-drm 1.0.0

---

## Build fix API changes
- MODULE_IMPORT_NS: string argument syntax in 6.13+
- pwm_chip.dev: now embedded struct device (not pointer)
- pwm_chip.base: removed; pwm->hwpwm replaces old index calculation
- platform_driver.remove: returns void (not int) in 6.11+
- IOMMU: pgsize_bitmap moved to iommu_domain; domain_alloc -> domain_alloc_paging
- no_llseek -> noop_llseek
- asm-generic/export.h: removed from kernel headers
- Timer API: del_timer -> timer_delete, del_timer_sync -> timer_delete_sync (6.15+)
- cfg80211: link_id params added to many callbacks (6.1+)
- cfg80211_ch_switch_notify: back to 3 args in 6.18 (link_id dropped from notify)
- set_monitor_channel, set_wiphy_params, set_tx_power: radio_idx param added (6.0+)

---

---

## HDMI Audio (AHUB driver)

H616/H618 has no standalone I2S controllers — all audio routes through
the Audio Hub (AHUB) at 0x05097000.

### Architecture
- APBIF0 (DMA port 3) → AHUB crossbar (RXCONT BIT(31)) → I2S1 → HDMI I2S input
- DW-HDMI auto-registers `dw-hdmi-i2s-audio.N.auto` when CONFIG0 I2S bit is set
- Simple-audio-card connects AHUB CPU DAI to dw-hdmi-i2s-audio codec

### Key register notes
- AHUB_GAT/RST: bit 31 = APBIF_TX0, bit 22 = I2S1
- AHUB_I2S_RXCONT(1): BIT(31) routes APBIF_TXDIF0 to I2S1 TX output
- APBIF_TX_TXIM=1: promotes DMA sample to MSB of 32-bit FIFO slot
  (required for left-justified I2S, which DW-HDMI expects in I2S mode)
- DW-HDMI requires bit_clk_provider=false → AHUB must be I2S master (CLK_OUT=1)
- HDMI_AUD_INPUTCLKFS = 64FS → BCLK = 64×fs (32 BCLK per channel, 32-bit slot)

### Files
- sound/soc/sunxi/sun50i-ahub.c — new driver (CONFIG_SND_SUN50I_AHUB=m)
- arch/arm64/boot/dts/allwinner/sun50i-h616.dtsi — ahub@5097000 node
- arch/arm64/boot/dts/allwinner/sun50i-h618-longanpi-3h.dts — enable ahub +
  simple-audio-card connecting ahub to hdmi

### Status (2026-03-29)
**WORKING** — confirmed on lpi3h-f1a0 with kernel 6.18.19-27.

Card registers as "HDMI Audio" (hw:Audio,0). Supports S16_LE/S24_LE/S32_LE,
stereo (2ch only), 32000–192000 Hz.

### To use on device
```sh
# Load modules (once; add to /etc/modules for persistence)
sudo modprobe sun50i-ahub
sudo modprobe snd-soc-simple-card
# List sound cards
aplay -l   # expect card "HDMI Audio"
# Test tone (must be stereo — device requires 2 channels)
speaker-test -D hw:Audio,0 -c 2 -t sine -f 440 -l 1
# Play audio (stereo files only)
aplay -D hw:Audio,0 stereo.wav
```

---

## Build output
Successfully produced .deb packages at /extra/LPI3H/LonganPi-3H-SDK/build/:
- linux-image-6.18.19_6.18.19-25_arm64.deb
- linux-headers-6.18.19_6.18.19-25_arm64.deb

Built from: longanpi_3h_defconfig (clean build)
Installed on lpi3h-f1a0 (2026-03-29), verified working:
- Panfrost Mali-G31 probes at 432 MHz (CONFIG_SUN50I_H6_PRCM_PPU=y required)
- HDMI display at 1280x720@60 via sun4i KMS
- mpv --vo=gpu with Panfrost renders 1280x720 H264 @ 30fps in real time
- kmscube confirms OpenGL ES 3.1 / Mali-G31 (Panfrost) pipeline

## AIC8800D80 Bluetooth — investigation result (2026-04-15)

**Conclusion: Classic BT (A2DP) not possible with this chip. BLE also unreachable.**

### What was found
The AIC8800D80 BT firmware operates in **RWNX mailbox mode** (`AICBT_BTPORT_MB`).
BT HCI events/responses flow through the WiFi interface (USB interface 2, EP 0x81 IN)
using the RWNX proprietary protocol — not through the USB BT class interface
(interface 0, EP 0x83 interrupt IN).

Confirmed via hciconfig: TX=3 bytes (HCI_Reset sent), RX=0 bytes (nothing returned
on EP 0x83), regardless of driver, timing, or WiFi init state.

The AIC8800DC chip works because its firmware starts in USB HCI mode by default.
The D80 firmware does not, and `fw_config()` (which activates USB HCI on DC) also
times out because the chip routes its response through the RWNX mailbox too.

**Additionally: LMP features byte 4 = 0x60 (BR/EDR Not Supported, LE Supported).**
The chip is BLE-only — no Classic Bluetooth, no A2DP, regardless of HCI access.

### Approaches exhausted
- Standard kernel btusb → HCI_Reset -110 (EP 0x83 never responds)
- aic_btusb (CONFIG_BLUEDROID=0) → HCI_Reset -110
- aic_btusb + fw_config called from btusb_open (after WiFi init) → fw_config -110
- Timing delays up to 3s after WiFi interface appears → no effect

### Getting BT to work would require
Implementing a BT HCI transport over the RWNX protocol inside aic8800_fdrv.
No public protocol documentation exists. Not worth pursuing.

### Recommendation
For Classic BT / A2DP: use an external USB Bluetooth Classic dongle (CSR8510,
BCM20702, etc.) — supported out-of-the-box by Linux btusb driver.

### Current board state
- `/etc/modprobe.d/aic8800-bt.conf`: blacklist aic_btusb
- kernel btusb=m (was changed from =y during investigation; no functional impact)
- No btusb-delayed.service; no udev BT rules

---

## Device configuration (lpi3h-f1a0)
- /etc/default/u-boot: video=HDMI-A-1:1280x720@60 (force mode for power-saving monitors)
- /etc/udev/rules.d/99-no-p2p.rules: removes p2p-dev-* interfaces on creation
- /etc/wpa_supplicant/wpa_supplicant.conf: p2p_disabled=1
- /etc/systemd/system/wpa_supplicant.service.d/no-p2p.conf: loads above config
- /etc/modprobe.d/aic8800-bt.conf: blacklist aic_btusb (BT unusable; see above)
