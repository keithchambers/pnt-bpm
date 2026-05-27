# pnt-cli

Batch tempo-change audio files with Serato Pitch n' Time LE — no DAW required.

## Requirements

- macOS 13 or newer
- Serato Pitch n' Time LE installed

## Install

Download [pnt-cli-1.0.0.pkg](https://github.com/keithchambers/pnt-cli/releases/download/v1.0.0/pnt-cli-1.0.0.pkg) and open it.

Verify:

```sh
pnt-cli --help
```

If Pitch n' Time LE isn't installed, the help is followed by a warning and `pnt-cli` exits 1.

## Usage

```sh
pnt-cli song.wav --source 120 --target 125,128
```

Renders `song_125bpm.wav` and `song_128bpm.wav` next to the input. Every input is rendered at every target, so multiple inputs fan out:

```sh
pnt-cli a.wav b.aiff --source 120 --target 125,128   # 4 renders
```

Output files keep the input's file format and live next to the input unless `--out-dir` is set.

If `--source` is omitted, `pnt-cli` auto-detects the source BPM from Beatport ID3 tags or filename slots (`..._(Mix)__<BPM>__<Key>.aiff`). If no source is detectable, `pnt-cli` errors out — pass `--source <BPM>` to be explicit.

## Flags

| Flag | Description |
| --- | --- |
| `-t, --target <BPM[,BPM...]>` | Target BPM(s). Required. Comma-separated or repeated. |
| `-i, --input <FILE>` | Input file. Can be repeated. Combined with positional inputs. |
| `-s, --source <BPM>` | Source BPM. Defaults to auto-detect. |
| `-d, --out-dir <DIR>` | Output directory. Defaults to input's directory. |
| `--overwrite` | Replace existing files. |
| `-h, --help` | Show help. |
| `-v, --version` | Show version. |

## Notes

- Outputs keep the input's sample rate, channel count, and file format.
- Source metadata and artwork are copied to outputs; the BPM tag is updated to the target BPM.
- MP3 inputs are rejected. Use WAV, AIFF, CAF, or M4A.

## Disclaimer

`pnt-cli` is an independent open-source project. It is not affiliated with, endorsed by, or sponsored by Serato, and does not include Serato Pitch n' Time — install and license Serato Pitch n' Time LE separately.
