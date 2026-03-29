# Docker Kernel Build — LPI3H

## State of the tree

- Source: `/extra/LPI3H/LonganPi-3H-SDK/build/linux/`
- Kernel: 6.18.19, base commit `4aea1dc4c`, 49 patches applied (HEAD `daf080d2a8dd`)
- Patches live in `linux.new/` — already applied; present for reference only
- Config: `longanpi_3h_defconfig`
- Output `.deb` files land in `/extra/LPI3H/LonganPi-3H-SDK/build/`

## Build the Docker image (once)

Run from `/extra/LPI3H/LonganPi-3H-SDK/docker`:

```sh
docker build --network=host -f Dockerfile -t kernelbuild .
```

Uses apt proxy `http://aptcacheserver:8000/` (primary) with automatic fallback to `http://localhost:8080/`. The Dockerfile probes `aptcacheserver:8000` at build time and selects whichever is reachable.

## Build the kernel

Run from `/extra/LPI3H/LonganPi-3H-SDK/`:

```sh
docker run --rm --network=host \
  --ulimit nofile=1048576:1048576 \
  --cpus="10" \
  -v /extra/LPI3H/LonganPi-3H-SDK:/sdk \
  kernelbuild \
  bash -c "cd /sdk && CROSS_COMPILE=aarch64-linux-gnu- bash mkkernel.sh"
```

`mkkernel.sh` runs `make longanpi_3h_defconfig` then `make bindeb-pkg`.

Add `--clean` to force `make clean` first (needed after config changes):

```sh
  bash -c "cd /sdk && CROSS_COMPILE=aarch64-linux-gnu- bash mkkernel.sh --clean"
```

## Critical constraints

- **Must bind-mount from `/extra/LPI3H/`** (ext4). Never from `/home/lou/Projects/` — that path is a FUSE/unionfs mount and causes `ar: Too many open files` regardless of ulimit.
- **`--ulimit nofile=1048576:1048576` is required.** Without it the build fails at the linking stage.
- **`--network=host` is required** for the apt proxy and for the container to reach it during image build.

## Stale x86-64 binaries (if build/linux was rsynced from longan-builder)

The source tree may contain x86-64 ELF binaries (fixdep, conf, etc.) built on longan-builder (glibc 2.34). These won't run in the container and must be deleted so they rebuild from source:

```sh
find /extra/LPI3H/LonganPi-3H-SDK/build/linux -type f -executable ! -name "*.sh" ! -name "*.py" ! -name "*.pl" | while read f; do
  file "$f" | grep -q "ELF.*x86-64" && rm "$f"
done
```

Run this before the first build after any rsync from longan-builder.

## Output

On success, `.deb` packages appear in `build/`:

```
build/linux-image-6.18.19+_<version>_arm64.deb
build/linux-headers-6.18.19+_<version>_arm64.deb
build/linux-libc-dev_<version>_arm64.deb
```

Install on the device via `dpkg -i` or the `mkimage.sh` pipeline.

## Applying new patches

Patches in `linux.new/` are already applied. To apply additional patches:

```sh
cd /extra/LPI3H/LonganPi-3H-SDK/build/linux
git am < ../../linux.new/XXXX-description.patch
```

To revert all patches back to the 6.18.19 base:

```sh
git reset --hard 4aea1dc4c
```
