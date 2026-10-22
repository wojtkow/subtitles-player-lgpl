#!/bin/bash
# Builds the FFmpeg XCFrameworks that the FFmpeg package links. They are not committed: run this script once after
# cloning, and again after changing the versions below, before opening or building the Xcode project.
#
#   Packages/FFmpeg/BuildFrameworks.sh
#
# Needs Xcode with the tvOS and iOS SDKs, curl, pkg-config, Meson, and Ninja (`brew install pkg-config meson ninja`). The
# script downloads the FFmpeg and dav1d source archives into a work directory, verifies their SHA-256 checksums, builds
# for tvOS and iOS arm64 devices and simulators, and writes Packages/FFmpeg/Frameworks/<library>.xcframework. FFmpeg's configure
# script does not accept paths with spaces, so the work directory defaults to the user's cache directory; set
# FFMPEG_WORK to use another path without spaces.
#
# FFmpeg is configured as in the PR 19 probe: LGPL version 2.1 or later, decoders, demuxers, and parsers only, with
# VideoToolbox, AudioToolbox, and dav1d for software AV1 decoding. dav1d (BSD 2-clause) is linked statically into
# libavcodec; each FFmpeg library is a dynamic framework so that it can be replaced as the LGPL requires.
set -euo pipefail

ffmpeg_version=9.0.2
ffmpeg_sha256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
dav1d_version=1.5.4
dav1d_sha256=686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5
minimum_tvos=26.1
minimum_ios=26.1
libraries=(libavcodec libavformat libavutil libswresample libswscale)
# The required-reason APIs that App Store Connect looks for in each framework, which must declare them in its own privacy
# manifest. FFmpeg uses file timestamp APIs only, for files in the app's container, which Privacy/PrivacyInfo.xcprivacy
# declares; a library that uses another category stops the build until the manifest declares it too.
timestamp_symbols='^_(stat|fstat|lstat|fstatat|getattrlist|getattrlistbulk|fgetattrlist|getattrlistat)$'
other_symbols='^_(statfs|statvfs|fstatfs|fstatvfs|mach_absolute_time)$'

package="$(cd "$(dirname "$0")" && pwd)"
work="${FFMPEG_WORK:-$(getconf DARWIN_USER_CACHE_DIR)net.peritum.subplayer.ffmpeg}"
output="$package/Frameworks"
case "$work" in
    *" "*)
        echo "The work directory must not contain spaces: $work" >&2
        exit 1
        ;;
esac
mkdir -p "$work"
jobs="$(sysctl -n hw.ncpu)"

fetch() {
    local url="$1" file="$2" checksum="$3"
    if [ ! -f "$work/$file" ]; then
        echo "Downloading $url"
        curl -fsSL -o "$work/$file.partial" "$url"
        mv "$work/$file.partial" "$work/$file"
    fi
    echo "$checksum  $work/$file" | shasum -a 256 -c - > /dev/null
}

fetch "https://ffmpeg.org/releases/ffmpeg-$ffmpeg_version.tar.xz" "ffmpeg-$ffmpeg_version.tar.xz" "$ffmpeg_sha256"
fetch "https://downloads.videolan.org/pub/videolan/dav1d/$dav1d_version/dav1d-$dav1d_version.tar.xz" \
    "dav1d-$dav1d_version.tar.xz" "$dav1d_sha256"
rm -rf "$work/ffmpeg-$ffmpeg_version" "$work/dav1d-$dav1d_version"
tar -xf "$work/ffmpeg-$ffmpeg_version.tar.xz" -C "$work"
tar -xf "$work/dav1d-$dav1d_version.tar.xz" -C "$work"

build_dav1d() {
    local platform="$1" sdk="$2" target="$3" subsystem="$4"
    local sysroot clang build="$work/dav1d-build-$platform" install="$work/dav1d-$platform"
    sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
    clang="$(xcrun --sdk "$sdk" --find clang)"
    rm -rf "$build" "$install"
    cat > "$work/dav1d-cross-$platform.txt" <<CROSS
[binaries]
c = ['$clang', '-target', '$target', '-isysroot', '$sysroot']
ar = '$(xcrun --sdk "$sdk" --find ar)'
strip = '$(xcrun --sdk "$sdk" --find strip)'

[host_machine]
system = 'darwin'
subsystem = '$subsystem'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
CROSS
    meson setup "$build" "$work/dav1d-$dav1d_version" --cross-file "$work/dav1d-cross-$platform.txt" \
        --prefix "$install" --libdir lib --buildtype release --default-library static \
        -Denable_tools=false -Denable_tests=false -Denable_docs=false > "$work/dav1d-$platform.log"
    ninja -C "$build" install >> "$work/dav1d-$platform.log"
}

build_ffmpeg() {
    local platform="$1" sdk="$2" target="$3"
    local build="$work/ffmpeg-build-$platform" install="$work/ffmpeg-$platform"
    rm -rf "$build" "$install"
    mkdir -p "$build"
    (
        cd "$build"
        PKG_CONFIG_LIBDIR="$work/dav1d-$platform/lib/pkgconfig" "$work/ffmpeg-$ffmpeg_version/configure" \
            --prefix="$install" \
            --enable-cross-compile \
            --target-os=darwin \
            --arch=arm64 \
            --cc="$(xcrun --sdk "$sdk" --find clang)" \
            --sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)" \
            --extra-cflags="-target $target" \
            --extra-ldflags="-target $target" \
            --pkg-config-flags=--static \
            --install-name-dir=@rpath \
            --enable-shared \
            --disable-static \
            --enable-pic \
            --disable-programs \
            --disable-doc \
            --disable-debug \
            --disable-avdevice \
            --disable-avfilter \
            --disable-encoders \
            --disable-muxers \
            --disable-devices \
            --disable-network \
            --disable-avfoundation \
            --disable-coreimage \
            --disable-securetransport \
            --enable-videotoolbox \
            --enable-audiotoolbox \
            --enable-libdav1d \
            > "$work/ffmpeg-configure-$platform.log"
        grep -q "^License: LGPL version 2.1 or later" "$work/ffmpeg-configure-$platform.log"
        make -j"$jobs" > "$work/ffmpeg-make-$platform.log" 2>&1
        make install >> "$work/ffmpeg-make-$platform.log" 2>&1
    )
}

# Adds the privacy manifest to the framework of a library that uses a file timestamp API.
add_privacy_manifest() {
    local binary="$1" imports
    imports="$(nm -u "$binary")"
    if grep -Eq "$other_symbols" <<< "$imports"; then
        echo "$(basename "$binary") uses a required-reason API that Privacy/PrivacyInfo.xcprivacy does not declare" >&2
        exit 1
    fi
    if grep -Eq "$timestamp_symbols" <<< "$imports"; then
        cp "$package/Privacy/PrivacyInfo.xcprivacy" "$(dirname "$binary")/PrivacyInfo.xcprivacy"
    fi
}

# Wraps each installed library in a framework whose install name and FFmpeg dependencies use @rpath framework paths.
make_frameworks() {
    local platform="$1" bundle_platform="$2" minimum="$3"
    local install="$work/ffmpeg-$platform" frameworks="$work/frameworks-$platform"
    rm -rf "$frameworks"
    for library in "${libraries[@]}"; do
        local framework="$frameworks/$library.framework" binary
        mkdir -p "$framework/Headers"
        binary="$(realpath "$install/lib/$library.dylib")"
        cp "$binary" "$framework/$library"
        cp -R "$install/include/$library/." "$framework/Headers/"
        install_name_tool -id "@rpath/$library.framework/$library" "$framework/$library"
        for dependency in $(otool -L "$framework/$library" | awk 'NR > 1 && $1 ~ /^@rpath\/lib/ { print $1 }'); do
            local name="${dependency#@rpath/}"
            name="${name%%.*}"
            install_name_tool -change "$dependency" "@rpath/$name.framework/$name" "$framework/$library"
        done
        strip -x "$framework/$library"
        add_privacy_manifest "$framework/$library"
        cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$library</string>
    <key>CFBundleIdentifier</key>
    <string>org.ffmpeg.$library</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$library</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$ffmpeg_version</string>
    <key>CFBundleVersion</key>
    <string>$ffmpeg_version</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$bundle_platform</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>$minimum</string>
</dict>
</plist>
PLIST
    done
}

# Each platform: its name, SDK, target triple, Meson subsystem, bundle platform, and minimum OS version.
platforms=(
    "tvos-device appletvos arm64-apple-tvos$minimum_tvos tvos AppleTVOS $minimum_tvos"
    "tvos-simulator appletvsimulator arm64-apple-tvos$minimum_tvos-simulator tvos-simulator AppleTVSimulator $minimum_tvos"
    "ios-device iphoneos arm64-apple-ios$minimum_ios ios iPhoneOS $minimum_ios"
    "ios-simulator iphonesimulator arm64-apple-ios$minimum_ios-simulator ios-simulator iPhoneSimulator $minimum_ios"
)
for entry in "${platforms[@]}"; do
    read -r platform sdk target subsystem bundle_platform minimum <<< "$entry"
    echo "Building dav1d $dav1d_version for $platform"
    build_dav1d "$platform" "$sdk" "$target" "$subsystem"
    echo "Building FFmpeg $ffmpeg_version for $platform"
    build_ffmpeg "$platform" "$sdk" "$target"
    make_frameworks "$platform" "$bundle_platform" "$minimum"
done

rm -rf "$output"
mkdir -p "$output"
for library in "${libraries[@]}"; do
    arguments=()
    for entry in "${platforms[@]}"; do
        arguments+=(-framework "$work/frameworks-${entry%% *}/$library.framework")
    done
    xcodebuild -create-xcframework "${arguments[@]}" -output "$output/$library.xcframework" > /dev/null
done
echo "Wrote ${libraries[*]} to $output"
