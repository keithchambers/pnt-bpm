# pnt-cli

## Overview

Serato Pitch n' Time provides the industry's leading pitch-shifting and time-stretching plugin in terms of overall musicality, helping producers and DJs change tempo while preserving pitch and avoiding the artifacts that cheaper time-stretch algorithms can introduce.

Serato only supports Pitch n' Time running in Logic Pro and Pro Tools DAWs. That is powerful for studio workflows, but it creates friction for repeatable batch work: launching a DAW, creating or opening a session, loading the plugin, setting tempo changes, bouncing files, and repeating the process for every target BPM.

`pnt-cli` eliminates that DAW dependency for macOS users who already have Serato Pitch n' Time LE installed locally. It hosts the installed Pitch n' Time Audio Unit directly from the command line, enabling Pitch n' Time users on macOS to convert the BPM of a track to a different BPM without changing pitch.

Example:

```sh
pnt-cli song.aiff --source 120 --target 125,128
```

This creates new rendered audio files at 125 BPM and 128 BPM using Serato Pitch n' Time for the tempo conversion.

`pnt-cli` is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Serato. It does not include Serato Pitch n' Time; users must install and license Serato Pitch n' Time LE separately.

## Installation

Requirements:

- macOS 13 or newer
- Serato Pitch n' Time LE installed locally

Download the macOS release package:

[pnt-cli-1.0.0.pkg](https://github.com/keithchambers/pnt-cli/releases/download/v1.0.0/pnt-cli-1.0.0.pkg)

Open `pnt-cli-1.0.0.pkg` and follow the installer prompts.

Verify that the CLI can load Serato Pitch n' Time:

```sh
pnt-cli --help
```

If Pitch n' Time LE isn't installed (or can't be loaded), `pnt-cli` prints
the help text followed by a warning explaining that Pitch n' Time LE is
required, and exits with status 1.

## Usage

Render one target BPM:

```sh
pnt-cli song.wav --source 120 --target 125
```

### Auto-detecting the source BPM (Beatport only)

If you omit `--source`, `pnt-cli` will try to read the BPM from a
Beatport-purchased track in one of two ways:

1. **ID3 `TBPM` frame** embedded in the file's metadata (Beatport
   typically writes this as an `ID3 ` chunk at the tail of the AIFF).
2. **Beatport filename slot** — the BPM that sits between double
   underscores in Beatport's naming convention,
   `Artist_Title_(Mix)__<BPM>__<Key>.aiff`.

```sh
# Either the ID3 TBPM frame or the __125__ slot in the filename works:
pnt-cli "Andrew_Meller_Bee_(Original_Mix)__125__Bb_Minor.aiff" --target 128
```

Values outside 50–220 BPM are rejected — this filters out Beatport's
older 7–8-digit track-IDs that occasionally appear in the same slot
(`__17628366__`). Nothing else is attempted: there is no parent-directory
walk, no generic metadata-key search, and no audio-content analysis. If
neither source is present, `pnt-cli` errors out and you should pass
`--source <BPM>` explicitly.

Render multiple target BPMs:

```sh
pnt-cli song.wav --source 120 --target 125,128
```

Render multiple source files at the same target BPMs in a single run. Every
input is warped to every target, so the command below produces six files
(three inputs × two targets):

```sh
pnt-cli a.wav b.wav c.aiff --source 120 --target 125,128
```

Those planned renders run concurrently by default — `pnt-cli` fans out across
the active CPU count reported by macOS, and each job loads its own Pitch n'
Time Audio Unit instance.

When `--source` is omitted with multiple inputs, the source BPM is detected
independently for each file — so a batch of Beatport tracks at different
tempos can be rendered to a shared target in one invocation:

```sh
pnt-cli "Artist_A_Track_A_(Original_Mix)__125__G_Minor.aiff" \
  "Artist_B_Track_B_(Extended_Mix)__128__A_Minor.aiff" \
  --target 124
```

Inputs can also be passed via repeated `-i`/`--input` flags, which is handy
when paths contain spaces or come from another command:

```sh
pnt-cli -i "track one.wav" -i "track two.wav" --source 120 --target 125,128
```

Write files to a specific directory:

```sh
pnt-cli song.aiff --source 120 --target 125,128 --out-dir renders
```

Overwrite existing output files:

```sh
pnt-cli song.aiff --source 120 --target 125,128 --overwrite
```

Rendered files automatically copy source track metadata and artwork when
present. If the source metadata includes a BPM field, the copied metadata
is updated to match each target BPM.

Output filenames use this fixed pattern (extension matches the input):

```text
song_125bpm.wav
song_128bpm.aiff
```

When rendering multiple inputs into a shared `--out-dir`, `pnt-cli` refuses
to start if two planned renders would write to the same output path (for
example, two files both named `song.wav` from different directories). This
collision check runs before concurrent jobs start. Rename one of the inputs
or render each one into its own directory to avoid the collision.

Outputs are written at the input sample rate, channel count, and file format.
