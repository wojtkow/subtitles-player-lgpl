# Sub Player LGPL materials

Sub Player for iOS and tvOS uses libraries under the GNU Lesser General Public License version 2.1 (LGPL 2.1). This
repository holds what the LGPL asks for, for each distributed version of the app: the exact sources of these libraries,
the scripts that build them, Sub Player's object files for relinking it with a modified library, and instructions.
Sub Player's own source code is not part of it.

## Libraries

| Library | Version | License | Source | In Sub Player |
| --- | --- | --- | --- | --- |
| AMSMB2 | 4.0.3, commit `1726aaaf7adf63d7d1d2a0c5d1b0e635028215c0` | LGPL 2.1 | <https://github.com/amosavian/AMSMB2/tree/4.0.3> | `AMSMB2.framework`, a dynamic framework |
| libsmb2 | commit `aff9fa6ba9f41cfd3c15d184554601ec3f6d8d03`, AMSMB2's submodule | LGPL 2.1 or, where its files say so, a later version | <https://github.com/sahlberg/libsmb2> | linked statically into `AMSMB2.framework` |
| FFmpeg | 9.0.2 | LGPL 2.1 or later | <https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz> | `libavcodec`, `libavformat`, `libavutil`, `libswresample`, and `libswscale`, dynamic frameworks built without GPL or non-free components |
| dav1d | 1.5.4 | BSD 2-clause | <https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/dav1d-1.5.4.tar.xz> | linked statically into `libavcodec` |

Each library keeps its own license. FFmpeg is a trademark of Fabrice Bellard.

## Contents

- `LICENSE`: the text of the LGPL 2.1.
- `scripts/fetch-sources.sh`: downloads the exact sources into `sources/` and verifies them: AMSMB2 and libsmb2 by
  their commits, and the FFmpeg and dav1d archives by their SHA-256 checksums.
- `ffmpeg/BuildFrameworks.sh`: the script that builds Sub Player's FFmpeg frameworks, unchanged, with the privacy
  manifest that it adds to them.
- `amsmb2/`: the package resolution for building AMSMB2 alone, and the privacy manifest that Sub Player adds to
  `AMSMB2.framework`.
- `RELINKING.md`: how to build a modified library and relink Sub Player with it.

## Versions

Each distributed version of Sub Player has a release in this repository, with archived copies of the library sources,
the relinking kit of each platform, and their checksums.

| Sub Player | Platforms | Xcode | Release |
| --- | --- | --- | --- |
| No version has been distributed yet. | | | |

## License

The scripts and documents of this repository, copyright 2016–2026 Peritum.Net, are available under the LGPL 2.1, as
`LICENSE` has it. The libraries' sources are under their own licenses.
