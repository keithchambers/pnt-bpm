# pnt-bpm

## Overview

Serato Pitch n' Time provides the industry's leading pitch-shifting and time-stretching plugin in terms of overall musicality, helping producers and DJs change tempo while preserving pitch and avoiding the artifacts that cheaper time-stretch algorithms can introduce.

Serato only supports Pitch n' Time running in Logic Pro and Pro Tools DAWs. That is powerful for studio workflows, but it creates friction for repeatable batch work: launching a DAW, creating or opening a session, loading the plugin, setting tempo changes, bouncing files, and repeating the process for every target BPM.

`pnt-bpm` eliminates that DAW dependency for macOS users who already have Serato Pitch n' Time LE installed locally. It hosts the installed Pitch n' Time Audio Unit directly from the command line, enabling Pitch n' Time users on macOS to convert the BPM of a track to a different BPM without changing pitch.

Example:

```sh
pnt-bpm song.aiff --source 120 --target 125,128
```

This creates new rendered audio files at 125 BPM and 128 BPM using Serato Pitch n' Time for the tempo conversion.

`pnt-bpm` is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Serato. It does not include Serato Pitch n' Time; users must install and license Serato Pitch n' Time LE separately.

## Installation

Requirements:

- macOS
- Serato Pitch n' Time LE installed locally
- Xcode Command Line Tools or Xcode
- Swift Package Manager, included with Apple's developer tools

Install Apple's developer tools if needed:

```sh
xcode-select --install
```

Clone and build:

```sh
git clone https://github.com/keithchambers/pnt-bpm.git
cd pnt-bpm
swift build -c release
```

Verify that the CLI can load Serato Pitch n' Time:

```sh
.build/release/pnt-bpm --doctor --verbose
```

Install the binary to `~/.local/bin`:

```sh
scripts/install.sh
```

Make sure `~/.local/bin` is on your `PATH`. For zsh, add this to `~/.zshrc` if needed:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

You can also install from a release zip by unpacking it and running:

```sh
./install.sh
```

## Usage

Render one target BPM:

```sh
pnt-bpm song.wav --source 120 --target 125
```

### Auto-detecting the source BPM

If you omit `--source`, `pnt-bpm` will try to figure out the source BPM from
the file itself, in this order:

1. **Embedded metadata** — ID3 `TBPM`, iTunes `tmpo`, and similar tags via
   AVFoundation. Works on most properly tagged tracks (e.g. Beatport AIFFs
   with an embedded ID3 chunk, MixedInKey-tagged files, anything with an
   iTunes-style "tmpo" atom).
2. **Filename** — Beatport's `..._(Mix)__BPM__Key.aiff` slot, or a trailing
   `-BPM` / `-BPM-key` token.
3. **Parent directories** — walks up to three ancestor folders. This is how
   mvsep.com stem layouts are detected: the per-track folder name carries
   the BPM (e.g. `andrew-meller-bee-original-mix-125-bb-minor/`) even
   though the stem WAVs themselves don't.

```sh
# Source BPM is read from the embedded ID3 TBPM tag:
pnt-bpm "Andrew_Meller_Bee_(Original_Mix)__125__Bb_Minor.aiff" --target 128

# Source BPM is read from the parent folder name:
pnt-bpm mvsep-out/andrew-meller-bee-original-mix-125-bb-minor/2025-01-16_all_in_ensemble/vocals.wav --target 128
```

Values outside 50–220 BPM are rejected as implausible — this filters out
Beatport's older 7–8-digit track-IDs and mvsep's `-1`, `-2` duplicate
suffixes. If detection fails, pass `--source <BPM>` explicitly.

Render multiple target BPMs:

```sh
pnt-bpm song.wav --source 120 --target 125,128
```

`--output` is accepted as an alias for `--target`:

```sh
pnt-bpm song.wav --source 120 --output 125,128
```

Write files to a specific directory:

```sh
pnt-bpm song.aiff --source 120 --target 125,128 --out-dir renders
```

Preview what will be rendered without writing files:

```sh
pnt-bpm song.aiff --source 120 --target 125,128 --dry-run
```

Overwrite existing output files:

```sh
pnt-bpm song.aiff --source 120 --target 125,128 --overwrite
```

Show detailed render ratios and progress:

```sh
pnt-bpm song.aiff --source 120 --target 125,128 --verbose
```

Default output names use this pattern:

```text
{title}_{bpm}bpm.wav
```

For example:

```text
song_125bpm.wav
song_128bpm.wav
```

Use a custom output naming pattern:

```sh
pnt-bpm song.aiff --source 120 --target 125 --name-template "{title}-serato-{bpm}.{ext}"
```

The current release writes WAV output at the input sample rate and channel count.
