# Kernel Upgrade Runbook — LonganPi 3H

## Context

This documents the process actually used to move the kernel baseline from
6.18.19 to 6.18.48 (2026-09-01), as a repeatable procedure for future
upgrades within the same major/minor line (e.g. 6.18.x → 6.18.y, or a similar
same-series bump). It is not a guide for jumping major kernel versions
(e.g. 6.18 → 6.19+) — that would need re-verifying which of the 69
`kernel_patches/` still apply and may need actual porting work, not just a
clean rebase.

---

## 1. Check what's current

```sh
curl -s https://www.kernel.org/ | grep -A2 longterm   # or check kernel.org directly
```

Compare against this repo's current base: see `## Kernel source (build/linux)`
in `CLAUDE.md` for the current `BASE_TAG`/`BASE_COMMIT`.

---

## 2. Dry-run the rebase before touching anything permanent

`build/linux` is a **shallow clone** (see `mklinux.sh`), but `git rebase`
works fine across shallow history since it operates on diffs, not ancestry.
This makes a dry run genuinely safe and fully reversible:

```sh
cd build/linux
git tag pre-rebase-attempt HEAD          # safety net — nothing else points at these commits
git fetch --depth=1 origin tag v6.18.48  # new base tag
git rebase --onto v6.18.48 v6.18.19 HEAD # v6.18.19 = old base tag
```

- **Success, no conflicts**: proceed to step 3.
- **Conflicts**: `git rebase --abort`, then `git reset --hard pre-rebase-attempt`
  to fully restore original state. Decide whether the conflicting patch(es)
  need manual porting before continuing — this happened for real during the
  6.7→6.18.19 port (see `kernel_patches/STATUS.md`), so it's not hypothetical.

If the rebase succeeds, `build/linux` is now live at the new base — this is
your working state going into the build test, not yet a permanent change to
patch files.

---

## 3. Build-test before committing to anything

```sh
docker build --network=host -f docker/Dockerfile -t lpi3h-build .   # if Dockerfile changed
bash run_docker.sh mkkernel.sh --clean
```

A clean build here doesn't prove it boots — go to step 4 before treating
this as done.

---

## 4. Boot-test on real hardware

Deploy to a live test board (see `feedback_test_board.md` memory / `.env`
`MACID` for which board is current):

```sh
scp build/linux-image-*.deb build/linux-headers-*.deb <board>:
ssh <board> 'sudo dpkg -i linux-image-*.deb linux-headers-*.deb'
```

`dpkg -i` regenerates `/boot/extlinux/extlinux.conf` (the *rootfs* copy) via
`u-boot-update`, with the new kernel as default (`l0`) and the previous one
as fallback (`l1`). **This rootfs copy is reference-only — U-Boot reads the
FAT boot partition's copy, not this one.** Update that too:

```sh
ssh <board> '
sudo mount -t vfat -o iocharset=utf8 /dev/mmcblkXp1 /mnt
sudo cp /boot/vmlinuz-<new-ver> /mnt/vmlinuz-<new-ver>
sudo cp /usr/lib/linux-image-<new-ver>/allwinner/sun50i-h618-longanpi-3h.dtb \
        /mnt/sun50i-h618-longanpi-3h-<new-ver>.dtb
sudo tee /mnt/extlinux/extlinux.conf > /dev/null <<EOF
timeout 30
default l0

label l0
    kernel /vmlinuz-<new-ver>
    fdt /sun50i-h618-longanpi-3h-<new-ver>.dtb
    append root=PARTUUID=4c503348-02 rootfstype=ext4 rootwait console=tty0 console=ttyS0,115200 earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60

label l1
    kernel /vmlinuz-<old-ver>
    fdt sun50i-h618-longanpi-3h.dtb
    append root=PARTUUID=4c503348-02 rootfstype=ext4 rootwait console=tty0 console=ttyS0,115200 earlycon clk_ignore_unused rw video=HDMI-A-1:1280x720@60
EOF
sudo umount /mnt && sync && sudo reboot
'
```

Note: the SD card device node varies by board — check `lsblk` first
(`mmcblk1` on some boards, `mmcblk0` on others; see `CLAUDE.md` for why).

### Verification checklist (run after reboot)

```sh
ssh <board> uname -r                                    # confirm new kernel booted
ssh <board> 'dmesg --level=err,crit,alert,emerg'         # should be empty
ssh <board> 'ip -brief link; lsmod | grep aic'           # WiFi
```

Then manually confirm:
- HDMI display comes up
- HDMI audio (`aplay -l` shows `card 0: HDMI Audio`, or a quick `speaker-test`)
- GPU: `glmark2-drm` full run (score should match the previous baseline
  within noise — see `## GPU benchmark` in `README.md`). **Takes 5-6 minutes
  — use a timeout ≥ 600000ms if scripting this.**
- PWM/SPI device nodes: `ls /sys/class/pwm/ /dev/spidev*`
- Video playback: `mpv --vo=gpu --gpu-context=drm --drm-device=/dev/dri/card0`
  per `docs/mpv_howto.md` (software decode — this is the supported path;
  see `kernel_patches/STATUS.md` for the state of hardware VPU decode)

If anything regresses, the `l1` extlinux entry boots the previous kernel —
no need to reflash.

---

## 5. Make it permanent

Only after the above passes:

```sh
cd build/linux
git format-patch <new-base-tag>..HEAD -o /tmp/newpatches --start-number 1
rm kernel_patches/*.patch
cp /tmp/newpatches/*.patch kernel_patches/
```

Then update, by hand:
- `mklinux.sh` — `BASE_TAG`/`BASE_COMMIT` (both the default values and the
  header comment)
- `kernel_patches/STATUS.md` — add an upgrade note at the top (see existing
  entries for the format), update the "Applied (N commits on top of...)"
  header and commit table
- `CLAUDE.md` — `## Kernel source (build/linux)` section: base commit, patch
  count, HEAD hash, revert command; also the one-line summary near the top
  of the file, and `mklinux.sh` description in the build-flow diagram
- `README.md` — `## Hardware status (kernel X.Y.Z)` header, patch count in
  the Step 3 description, and the `## GPU benchmark` numbers (re-run
  `glmark2-drm` on the new kernel rather than assuming they're unchanged)

Commit only after all of the above are consistent — a partially-updated set
of version strings across these files is worse than not updating any of
them, since it's actively misleading about which files describe current
reality.

---

## Known pitfalls (hit these for real during the 6.18.19→6.18.48 upgrade)

- **`build/linux` is a shallow clone.** Don't assume normal git history
  operations work the same way — `git rebase --onto` across shallow history
  works because it diffs, but don't reach for anything that needs full
  ancestry (e.g. `git log --all --graph` won't show much).
- **Docker's kernel cross-build container caches `linux-image`/`linux-headers`
  `.deb`s in `build/` across runs** — `mkkernel.sh` prunes to the two most
  recent build versions automatically, but if testing multiple kernel
  versions back-to-back, double check which `.deb` you're actually deploying.
- **The FAT boot partition and the rootfs's `/boot/extlinux/extlinux.conf`
  are two separate files that can drift.** `dpkg -i` on a `linux-image`
  package only updates the rootfs copy. Forgetting the FAT partition step
  means the board keeps booting the old kernel despite the new one being
  "installed."
