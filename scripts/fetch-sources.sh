#!/bin/bash
# Downloads the exact sources of the LGPL libraries in Sub Player into sources/ and verifies them:
#
#   scripts/fetch-sources.sh
#
# AMSMB2 is cloned at its release tag and checked against its commit, with its libsmb2 submodule at the commit that
# AMSMB2 pins, and gets amsmb2/Package.resolved, which pins swift-atomics, a dependency of its tests only, as Sub Player
# resolved it. The FFmpeg and dav1d source archives are checked against their SHA-256 checksums; ffmpeg/BuildFrameworks.sh
# downloads and checks the same archives when it builds them. Needs git, curl, and shasum.
set -euo pipefail

amsmb2_version=4.0.3
amsmb2_commit=1726aaaf7adf63d7d1d2a0c5d1b0e635028215c0
libsmb2_commit=aff9fa6ba9f41cfd3c15d184554601ec3f6d8d03
ffmpeg_version=9.0.2
ffmpeg_sha256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
dav1d_version=1.5.4
dav1d_sha256=686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5

sources="$(cd "$(dirname "$0")/.." && pwd)/sources"
mkdir -p "$sources"

fetch() {
    local url="$1" file="$2" checksum="$3"
    if [ ! -f "$sources/$file" ]; then
        echo "Downloading $url"
        curl -fsSL -o "$sources/$file.partial" "$url"
        mv "$sources/$file.partial" "$sources/$file"
    fi
    echo "$checksum  $sources/$file" | shasum -a 256 -c - > /dev/null
    echo "Verified $file"
}

if [ ! -d "$sources/AMSMB2" ]; then
    echo "Cloning AMSMB2 $amsmb2_version"
    git clone --quiet --branch "$amsmb2_version" https://github.com/amosavian/AMSMB2.git "$sources/AMSMB2"
fi
git -C "$sources/AMSMB2" -c advice.detachedHead=false checkout --quiet "$amsmb2_commit"
git -C "$sources/AMSMB2" submodule --quiet update --init
if [ "$(git -C "$sources/AMSMB2" rev-parse HEAD)" != "$amsmb2_commit" ] ||
    [ "$(git -C "$sources/AMSMB2/Dependencies/libsmb2" rev-parse HEAD)" != "$libsmb2_commit" ]; then
    echo "AMSMB2 or libsmb2 is not at the expected commit" >&2
    exit 1
fi
cp "$(dirname "$sources")/amsmb2/Package.resolved" "$sources/AMSMB2/Package.resolved"
echo "Verified AMSMB2 $amsmb2_version at $amsmb2_commit and libsmb2 at $libsmb2_commit"

fetch "https://ffmpeg.org/releases/ffmpeg-$ffmpeg_version.tar.xz" "ffmpeg-$ffmpeg_version.tar.xz" "$ffmpeg_sha256"
fetch "https://downloads.videolan.org/pub/videolan/dav1d/$dav1d_version/dav1d-$dav1d_version.tar.xz" \
    "dav1d-$dav1d_version.tar.xz" "$dav1d_sha256"
echo "The sources are in $sources"
