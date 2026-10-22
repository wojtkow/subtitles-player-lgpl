# Relinking Sub Player with a modified library

The LGPL lets you change AMSMB2, libsmb2, or FFmpeg and use Sub Player with your changed library. Sub Player embeds
each of these libraries as a dynamic framework, and each version's relinking kit holds the app's object files. You can
therefore build your library, link the app with it, and sign the result with your own Apple developer account.

## What you need

- A Mac with the Xcode version that the release of the Sub Player version names, with its iOS or tvOS SDK. Swift
  object files link only with the compiler that built them.
- An Apple developer account, free or paid, and a device registered to it, to sign and install the app.
- For FFmpeg: `curl`, `pkg-config`, Meson, and Ninja, for example with `brew install pkg-config meson ninja`.

## 1. Get the sources

    scripts/fetch-sources.sh

The script puts AMSMB2 with libsmb2 in `sources/AMSMB2` and the FFmpeg and dav1d archives in `sources/`. The release of
each Sub Player version also has archived copies of them.

## 2. Build your library

### AMSMB2 or libsmb2

Change the sources in `sources/AMSMB2`, where libsmb2 is in `Dependencies/libsmb2`, and build the framework for your
platform:

    cd sources/AMSMB2
    xcodebuild -scheme AMSMB2 -destination 'generic/platform=iOS' -configuration Release \
        -derivedDataPath ../../build/amsmb2 CODE_SIGNING_ALLOWED=NO

Use `generic/platform=tvOS` for Apple TV. The framework is
`build/amsmb2/Build/Products/Release-iphoneos/PackageFrameworks/AMSMB2.framework`, or `Release-appletvos` for Apple
TV. Keep the public interface that Sub Player uses, since the app's object files link against its symbols.

### FFmpeg

`ffmpeg/BuildFrameworks.sh` downloads the FFmpeg and dav1d archives, checks their checksums, and builds the five
frameworks for iOS and tvOS devices and simulators into `ffmpeg/Frameworks/<library>.xcframework`. To build changed
sources:

1. Unpack `ffmpeg-9.0.2.tar.xz`, change the sources, and pack them again under the same name, as a `.tar.xz` archive
   whose top folder is `ffmpeg-9.0.2`.
2. Put the archive into the script's work directory, a path without spaces that `FFMPEG_WORK` sets, and change
   `ffmpeg_sha256` in the script to the archive's new checksum, which `shasum -a 256` prints.
3. Run the script:

       FFMPEG_WORK=/path/without/spaces ffmpeg/BuildFrameworks.sh

A platform's framework is in `ffmpeg/Frameworks/<library>.xcframework/ios-arm64/` for iPhone and iPad, or
`tvos-arm64/` for Apple TV. Keep the functions that Sub Player calls, and keep FFmpeg's LGPL configuration: the script
stops when configure reports another license.

## 3. Relink Sub Player

From the first distributed version on, each version's release has a relinking kit for each platform,
`SubPlayer-<version>-<platform>-relink.zip`. It holds:

- Sub Player's object files and the file list that the linker reads;
- `link.sh`, with the link command of that version's Release build;
- the app's resources, `Info.plist`, and entitlements, and the frameworks that the version was built with;
- the kit's own instructions for that version.

Replace a framework in the kit's `Frameworks` folder with yours, run `link.sh`, and sign the app as the kit describes,
with your own bundle identifier, team, and provisioning profile. Entitlements that need Apple's approval, such as
multicast networking for DLNA discovery, are not available to your account, so the kit's instructions leave them out;
the app then works without the features that they enable.

## 4. Install

Install the signed app on your device with Xcode's Devices and Simulators window, or with:

    xcrun devicectl device install app --device <device> SubPlayer.app
