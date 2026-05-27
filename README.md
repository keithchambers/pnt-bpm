<div align="center">
  <h1>pnt-cli</h1>
  <p><strong>Batch tempo-change audio files with Serato Pitch n' Time LE — no DAW required</strong></p>
</div>

## Overview

Serato Pitch n' Time (PnT) is the industry-standard pitch-shifting and time-stretching plugin for producers and DJs. It
changes a track's tempo while preserving its pitch, avoiding the artifacts that cheaper time-stretch algorithms
introduce.

PnT requires Logic Pro and Pro Tools, which is not automation friendly.

`pnt-cli` brings PnT to the command line. It hosts the locally installed Pitch n' Time Audio Unit directly from a
terminal and enables parallel processing of multiple tracks for fast batch processing.

## Installation

**Requirements:** macOS 13 or later with Serato Pitch n' Time LE 3.1.1 installed

Download the latest signed installer and open it: [pnt-cli-1.0.0.pkg](https://github.com/keithchambers/pnt-cli/releases/download/v1.0.0/pnt-cli-1.0.0.pkg)

_Note: If Pitch n' Time LE isn't installed (or can't be loaded), `pnt-cli` prints the help text followed by a warning._

## Quick Start

Render one input to multiple target BPMs:

```sh
pnt-cli song.wav --source 120 --target 125,128
# writes song_125bpm.wav and song_128bpm.wav next to the input
```

Render multiple inputs to multiple targets in a single batch — every input is rendered at every target:

```sh
pnt-cli vocals.wav drums.wav bass.wav --source 126 --target 120,124,128 -d renders/
# 3 inputs × 3 targets = 9 renders, all written to ./renders/
```

Let `pnt-cli` auto-detect the source BPM from Beatport ID3 tags or filename slots:

```sh
pnt-cli "Andrew_Meller_Bee_(Original_Mix)__125__Bb_Minor.aiff" --target 128
# detects 125 BPM from the filename, then renders one file at 128 BPM
```

Output tracks keep the input track's file format, sample rate, and channel count.
