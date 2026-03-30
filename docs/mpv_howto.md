# mpv on LonganPi 3H — GPU Rendering with Panfrost

## Prerequisites

- Kernel built with `CONFIG_SUN50I_H6_PRCM_PPU=y` (required for Panfrost to probe)
- HDMI display connected
- seatd installed (seat manager; required for DRM access from TTY without a display manager)
- mpv installed

```sh
sudo apt install seatd mpv
sudo usermod -aG video $USER   # seatd grants DRM access to the video group
# log out and back in for group membership to take effect
```

Both packages use default Debian config — no further customization needed.

## Verify Panfrost is working

```sh
ls /dev/dri/
# Expected: card0  card1  renderD128
# card0  = sun4i KMS (display engine / scanout)
# card1  = Panfrost GPU (3D render)
# renderD128 = Panfrost render node
```

If `renderD128` is absent, Panfrost failed to probe — check `dmesg | grep -i panfrost`.

## mpv config (~/.config/mpv/mpv.conf)

```ini
# Panfrost GPU rendering via DRM/KMS
vo=gpu
gpu-context=drm
drm-device=/dev/dri/card0
hwdec=v4l2request
```

**Notes:**
- `drm-device=card0` selects the sun4i KMS device for scanout. Panfrost (renderD128) is
  discovered automatically via EGL/PRIME — no extra config needed.
- `hwdec=v4l2request` enables Cedrus VPU hardware decode (H264/HEVC). In mpv 0.35.1
  this is silently ignored when `vo=gpu` is active (no DMA-BUF interop between Cedrus
  and Panfrost in that version). H264 decoding falls back to software (ARM cores),
  which handles 720p @ 30fps comfortably. Keep the line for future mpv versions.

## Test playback

```sh
mpv --vo=gpu --gpu-context=drm --drm-device=/dev/dri/card0 video.mp4
```

Or just `mpv video.mp4` if the config file is in place.

## Verify GPU rendering is active

Run with verbose output:

```sh
mpv --msg-level=all=v video.mp4 2>&1 | grep -i "panfrost\|OpenGL\|EGL\|renderer"
```

Expected output includes:

```
Renderer: Mali-G31 (Panfrost)
OpenGL ES 3.1
```

## kmscube (optional GPU smoke test)

```sh
sudo apt install kmscube
kmscube
# Should show a spinning cube on the HDMI display
# Confirm output: "Mali-G31 (Panfrost)" / "OpenGL ES 3.1"
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `renderD128` missing | Panfrost not probed | Check `dmesg | grep panfrost`; kernel needs `CONFIG_SUN50I_H6_PRCM_PPU=y` |
| Black screen / no display | Wrong KMS device | Ensure `drm-device=card0` (sun4i), not card1 |
| `[vo/gpu] No usable GPUs found` | EGL can't find render node | Check `/dev/dri/renderD128` exists and is readable |
| mpv opens but no window | Headless / SSH without display | Use a local terminal or `ssh -X` |
| choppy 1080p | Software decode + GPU render | 720p @ 30fps is the practical ceiling without hwdec interop |
