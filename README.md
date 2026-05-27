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

### Auto-detecting the source BPM (Beatport only)

If you omit `--source`, `pnt-bpm` will try to read the BPM from a
Beatport-purchased track in one of two ways:

1. **ID3 `TBPM` frame** embedded in the file's metadata (Beatport
   typically writes this as an `ID3 ` chunk at the tail of the AIFF, and
   in the ID3v2 header of the MP3 download).
2. **Beatport filename slot** — the BPM that sits between double
   underscores in Beatport's naming convention,
   `Artist_Title_(Mix)__<BPM>__<Key>.aiff`.

```sh
# Either the ID3 TBPM frame or the __125__ slot in the filename works:
pnt-bpm "Andrew_Meller_Bee_(Original_Mix)__125__Bb_Minor.aiff" --target 128
```

Values outside 50–220 BPM are rejected — this filters out Beatport's
older 7–8-digit track-IDs that occasionally appear in the same slot
(`__17628366__`). Nothing else is attempted: there is no parent-directory
walk, no generic metadata-key search, and no audio-content analysis. If
neither source is present, `pnt-bpm` errors out and you should pass
`--source <BPM>` explicitly.

Render multiple target BPMs:

```sh
pnt-bpm song.wav --source 120 --target 125,128
```

Render multiple source files at the same target BPMs in a single run. Every
input is warped to every target, so the command below produces six files
(three inputs × two targets):

```sh
pnt-bpm a.wav b.wav c.aiff --source 120 --target 125,128
```

When `--source` is omitted with multiple inputs, the source BPM is detected
independently for each file — so a batch of Beatport tracks at different
tempos can be rendered to a shared target in one invocation:

```sh
pnt-bpm track-a-125.aiff track-b-128.aiff --target 124
```

Inputs can also be passed via repeated `-i`/`--input` flags, which is handy
when paths contain spaces or come from another command:

```sh
pnt-bpm -i "track one.wav" -i "track two.wav" --source 120 --target 125,128
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

When rendering multiple inputs into a shared `--out-dir`, `pnt-bpm` refuses
to start if two inputs would write to the same output path (for example,
two files both named `song` from different directories). Rename one of the
inputs or render each one into its own directory to avoid the collision.

The current release writes WAV output at the input sample rate and channel count.
