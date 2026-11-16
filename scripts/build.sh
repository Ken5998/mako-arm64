#!/usr/bin/env bash
# Builds the MAKO Renderer pinned in upstream.json natively for aarch64 and
# packages it the way upstream packages its standalone Renderer:
#
#   OUT/MAKO-Renderer-vUPSTREAM-linux-arm64.tar.gz
#
# The archive holds upstream's own "Install MAKO Renderer" script, its
# checksummed install manifest and the bin/ lib/ share/ tree it copies into
# ~/.local: the Vulkan layer, the spatial scaling layer, mako-launch, the CLI
# and the Qt configuration app. MAKO FG has no aarch64 build, so its prebuilt
# x86-64 host and its model are added from the pinned Hugging Face revision;
# on ArmadaOS the host runs through FEX.
#
# Usage: scripts/build.sh [OUT]
#   WORK=dir      where sources and build trees go (default: build/)
#   MAKO_TESTS=1  also build upstream's tests and run them with ctest;
#                 CTEST_ARGS adds arguments to ctest (for example -E regex)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/out}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
work="${WORK:-$root/build}"
mkdir -p "$work"
work="$(cd "$work" && pwd)"
version="$(tr -d '[:space:]' < "$root/VERSION")"

pin() {
  python3 -c '
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    value = value[key]
print(value)' "$root/upstream.json" "$1"
}

mako_repo="$(pin mako.repository)"
mako_commit="$(pin mako.commit)"

# MAKO source at the pinned commit, with this repository's patches on top.
src="$work/mako"
if [ "$(git -C "$src" rev-parse HEAD 2>/dev/null || true)" != "$mako_commit" ]; then
  rm -rf "$src"
  git init -q "$src"
  git -C "$src" fetch -q --depth 1 "$mako_repo" "$mako_commit"
  git -C "$src" checkout -q --detach FETCH_HEAD
fi
git -C "$src" reset -q --hard "$mako_commit"
git -C "$src" clean -q -fdx
for patch in "$root"/patches/*.patch; do
  [ -e "$patch" ] || continue
  echo "Applying $(basename "$patch")"
  git -C "$src" apply "$patch"
done
upstream_version="$(tr -d '[:space:]' < "$src/engine/VERSION")"

# The Vulkan-Headers release upstream builds against.
headers_tag="$(tr -d '[:space:]' < "$src/engine/vulkan-headers-revision.txt")"
headers="$work/vulkan-headers-$headers_tag"
if [ ! -f "$headers/include/vulkan/vulkan_core.h" ]; then
  rm -rf "$headers"
  git clone -q --depth 1 --branch "$headers_tag" https://github.com/KhronosGroup/Vulkan-Headers "$headers"
fi

name="MAKO-Renderer-v$upstream_version-linux-arm64"
stage="$work/$name"
rm -rf "$stage"

testing=OFF
[ "${MAKO_TESTS:-0}" = 1 ] && testing=ON
# Same options as upstream's package-local.sh, without the 32-bit layer
# (there are no 32-bit ARM games to serve). The layers carry their own C++
# runtime so they load into any game, whatever libstdc++ it brings.
cmake -S "$src/engine" -B "$work/cmake" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER="${CXX:-clang++}" \
  -DCMAKE_INSTALL_PREFIX="$stage" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_SHARED_LINKER_FLAGS="-static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL" \
  -DBUILD_TESTING="$testing" \
  -DMAKO_VULKAN_HEADERS_INCLUDE_DIR="$headers/include" \
  -DMAKO_BUILD_VK_LAYER=ON \
  -DMAKO_BUILD_UI=ON \
  -DMAKO_BUILD_CLI=ON \
  -DMAKO_INSTALL_XDG_FILES=ON \
  -DMAKO_LAYER_LIBRARY_PATH="../../../lib/libmako-render.so" \
  -DMAKO_SCALING_LAYER_LIBRARY_PATH="../../../lib/libmako-render-scaling.so"
cmake --build "$work/cmake"
if [ "$testing" = ON ]; then
  # shellcheck disable=SC2086
  ctest --test-dir "$work/cmake" --output-on-failure ${CTEST_ARGS:-}
fi
cmake --install "$work/cmake" --strip

# MAKO FG: the model and the x86-64 host from the pinned revision, each file
# checked against the hash recorded in upstream.json.
fg_repo="$(pin mako_fg.repository)"
fg_revision="$(pin mako_fg.revision)"
fg_cache="$work/mako-fg-$fg_revision"
mkdir -p "$fg_cache"
python3 -c '
import json, sys
for name, sha in json.load(open(sys.argv[1]))["mako_fg"]["files"].items():
    print(sha, name)' "$root/upstream.json" > "$work/mako-fg.sha256"
while read -r sha file; do
  target="$fg_cache/$file"
  if [ ! -f "$target" ] || [ "$(sha256sum "$target" | cut -d' ' -f1)" != "$sha" ]; then
    mkdir -p "$(dirname "$target")"
    curl -fsSL --retry 3 -o "$target.part" "$fg_repo/resolve/$fg_revision/$file"
    mv "$target.part" "$target"
  fi
done < "$work/mako-fg.sha256"
(cd "$fg_cache" && sha256sum --check --quiet "$work/mako-fg.sha256")
install -Dm0755 "$fg_cache/runtime/x64/bin/mako-fg-host" "$stage/lib/mako-fg/mako-fg-host"
install -Dm0644 "$fg_cache/version.json" "$stage/lib/mako-fg/version.json"
for model in "$fg_cache"/model/*; do
  install -Dm0644 "$model" "$stage/lib/mako-fg/model/$(basename "$model")"
done
install -Dm0644 "$fg_cache/LICENSE" "$stage/share/doc/mako-render/mako-fg/LICENSE"
install -Dm0644 "$fg_cache/runtime/THIRD_PARTY_NOTICES" "$stage/share/doc/mako-render/mako-fg/THIRD_PARTY_NOTICES"

# This repository's notes next to upstream's licences.
install -Dm0644 "$root/README.md" "$stage/share/doc/mako-render/arm64/README.md"
install -Dm0644 "$root/upstream.json" "$stage/share/doc/mako-render/arm64/upstream.json"

# The packaged tree must be the native aarch64 build, with both manifests
# pointing at the 64-bit libraries.
check_arm64() {
  if ! readelf -h "$1" | grep -q 'AArch64'; then
    echo "Packaging failed: $1 is not an aarch64 binary" >&2
    exit 1
  fi
}
for binary in lib/libmako-render.so lib/libmako-render-scaling.so bin/mako-cli bin/mako-ui; do
  check_arm64 "$stage/$binary"
done
for manifest in \
    share/vulkan/implicit_layer.d/VkLayer_MAKO_render.json \
    share/mako-render/vulkan/implicit_layer.d/VkLayer_MAKO_render.json \
    share/vulkan/implicit_layer.d/VkLayer_MAKO_spatial_scaling.json \
    share/mako-render/vulkan/spatial_scaling.d/VkLayer_MAKO_spatial_scaling.json; do
  grep -q '"library_arch": "64"' "$stage/$manifest" || {
    echo "Packaging failed: $manifest is not a 64-bit layer manifest" >&2
    exit 1
  }
done
[ -x "$stage/bin/mako-launch" ] || { echo "Packaging failed: bin/mako-launch missing" >&2; exit 1; }

# Upstream's installer, its version file and checksummed manifest.
cp "$src/engine/scripts/mako-installer" "$stage/Install MAKO Renderer"
chmod 0755 "$stage/Install MAKO Renderer"
sed -e "s/@UPSTREAM_VERSION@/$upstream_version/g" -e "s/@VERSION@/$version/g" \
  "$root/dist/README.txt" > "$stage/README.txt"
printf '%s\n' "$upstream_version-arm64-$version" > "$stage/MAKO-Renderer-version.txt"
(
  cd "$stage"
  find bin lib share -type f -print | LC_ALL=C sort | xargs -d '\n' sha256sum
) > "$stage/MAKO-Renderer-install-manifest.txt"
(cd "$stage" && sha256sum --check --quiet MAKO-Renderer-install-manifest.txt)

tar -C "$work" -czf "$out/$name.tar.gz" "$name"
echo "Built $out/$name.tar.gz"
