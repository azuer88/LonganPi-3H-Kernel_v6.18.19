# Docker Build — LPI3H

Single image (`lpi3h-build`) for both kernel and rootfs builds.

## Build the Docker image (once)

Run from `/extra/LPI3H/LonganPi-3H-SDK/`:

```sh
docker build --network=host -f docker/Dockerfile -t lpi3h-build .
```

Uses apt proxy `http://aptcacheserver:8000/` (primary) with automatic fallback to `http://localhost:8080/`.

## Build the kernel

```sh
docker run --rm --network=host \
  --ulimit nofile=1048576:1048576 \
  --cpus="10" \
  -v /extra/LPI3H/LonganPi-3H-SDK:/sdk \
  lpi3h-build \
  bash -c "cd /sdk && CROSS_COMPILE=aarch64-linux-gnu- bash mkkernel.sh"
```

Add `--clean` after config changes:

```sh
  bash -c "cd /sdk && CROSS_COMPILE=aarch64-linux-gnu- bash mkkernel.sh --clean"
```

## Build the rootfs

Requires `--privileged` for mmdebstrap chroot:

```sh
docker run --rm --privileged --network=host \
  -v /extra/LPI3H/LonganPi-3H-SDK:/sdk \
  lpi3h-build \
  bash -c "cd /sdk && bash mkrootfs.sh"
```

## Critical constraints

- **Must bind-mount from `/extra/LPI3H/`** (ext4). Never from `/home/lou/Projects/` — FUSE/unionfs causes `ar: Too many open files`.
- **`--ulimit nofile=1048576:1048576`** required for kernel link stage.
- **`--network=host`** required for apt proxy.
- **`--privileged`** required for rootfs build (mmdebstrap needs real root for arm64 cross-bootstrap).

## Stale x86-64 binaries (if build/linux was rsynced from longan-builder)

```sh
find /extra/LPI3H/LonganPi-3H-SDK/build/linux -type f -executable ! -name "*.sh" ! -name "*.py" ! -name "*.pl" | while read f; do
  file "$f" | grep -q "ELF.*x86-64" && rm "$f"
done
```

Run before the first build after any rsync from longan-builder.

## Output

Kernel debs land in `build/`:
```
build/linux-image-6.18.19_<version>_arm64.deb
build/linux-headers-6.18.19_<version>_arm64.deb
build/linux-libc-dev_<version>_arm64.deb
```

Rootfs image: `build/rootfs_base.ext4`

## Applying new patches

```sh
cd /extra/LPI3H/LonganPi-3H-SDK/build/linux
git am < ../../linux.new/XXXX-description.patch
```

Revert all patches to 6.18.19 base:
```sh
git reset --hard 4aea1dc4c
```
