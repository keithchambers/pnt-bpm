<div align="center">
  <h1>pnt-cli</h1>
  <p><strong>Batch tempo-change audio files with Serato Pitch n' Time LE — no DAW required</strong></p>

  <p>
    <a href="https://github.com/keithchambers/pnt-cli/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/keithchambers/pnt-cli/ci.yml?branch=main&label=build" alt="Build Status"></a>
    <a href="https://github.com/keithchambers/pnt-cli/releases/latest"><img src="https://img.shields.io/github/v/release/keithchambers/pnt-cli?label=release" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey" alt="Platform: macOS 13+">
  </p>
</div>

## Overview

Serato Pitch n' Time is the industry-standard pitch-shifting and time-stretching plugin for producers and DJs. It
changes a track's tempo while preserving its pitch, avoiding the artifacts that cheaper time-stretch algorithms
introduce. Serato ships Pitch n' Time as a plugin that only loads inside Logic Pro and Pro Tools, which turns one-off
tempo changes into a multi-step ritual: launch a DAW, create a session, load the plugin, set the tempo, bounce,
repeat.

`pnt-cli` brings Pitch n' Time LE to the command line. It hosts the locally installed Pitch n' Time Audio Unit
directly from a terminal, so a track — or a folder of tracks — can be rendered to one or more target BPMs in a single
command. Source metadata and artwork are copied to each output, and the BPM tag is updated to match the target.

`pnt-cli` is an independent open-source project. It is not affiliated with, endorsed by, or sponsored by Serato, and
does not include Pitch n' Time — install and license Pitch n' Time LE separately.

## Installation

**Requirements:** macOS 13 or newer, with Serato Pitch n' Time LE installed locally.

Download the latest signed installer and open it:

[pnt-cli-1.0.0.pkg](https://github.com/keithchambers/pnt-cli/releases/download/v1.0.0/pnt-cli-1.0.0.pkg)

If Pitch n' Time LE isn't installed (or can't be loaded), `pnt-cli` prints the help text followed by a warning and
exits with status 1.

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

Outputs keep the input's file format, sample rate, and channel count.
