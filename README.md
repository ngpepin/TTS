
# TTS 
#### Convert a markdown file into an audio narration using VCTK and Coqui-TT

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A Bash script that converts Markdown files into narrated audio using **Text-to-Speech (TTS)** via Docker and the **Coqui-TTS** framework.

## Features

- Converts a Markdown (`.md`) file to **MP3 audio**.
- Uses the VCTK **multi-speaker TTS** model with customizable voices.
- Cleans Markdown syntax (headings, links, code blocks, etc.) for more natural-sounding speech.
- Splits large files into manageable chunks for processing.
- Optional **playback** of the generated audio.

## Prerequisites

- **Docker** (with GPU support recommended for faster synthesis)
- **Docker Compose**
- **Python 3** (for model invocation and Markdown cleaning)
- **ffmpeg** (for audio processing)
- **mp3wrap** (for merging audio chunks)
- **str** (for string manipulation)

## Installation

1. Clone the repository:

   ``` bash
   git clone https://github.com/ngpepin/TTS.git
   cd narrate-md

2. Make the script executable:

   ``` bash
   chmod +x narrate-md.sh

3. (Optional) Place the script in your `PATH` for global access:

   ``` bash
   sudo ln -s $(pwd)/narrate-md.sh /usr/local/bin/narrate-md
   ```

## Usage

``` bash
   ./narrate-md.sh [-p] <input.md>
```

### Options

``` text
| Flag | Description                          |
| ---- | ------------------------------------ |
| `-p` | Play the generated audio immediately |
```

### Example

``` bash
./narrate-md.sh -p README.md  # Converts README.md to README.mp3 and plays it
```

## Configuration

Edit these variables in the script to customize behavior:

``` bash
MODEL="tts_models/en/vctk/vits"  # TTS model (default: VCTK multi-speaker)
SPEAKER="p230"                   # Speaker ID (e.g., p230-p260 for VCTK)
MAX_LINES_PER_CHUNK=20           # Split large files into chunks of this size
```

## Technical Details

### Pipeline

1. **Markdown Cleaning**:

   * Strips headings, links, code blocks, and formatting

   * Adds pauses for punctuation (e.g., commas → ",,")

2. **Audio Generation**:

   * Uses Coqui-TTS in a Docker container

   * Converts text to WAV → MP3 with tempo adjustment

3. **Chunk Handling**:

   * Splits large files (>20 lines by default)

   * Merges chunks into a single MP3

### Supported Models

* **VCTK**: Multi-speaker English (113 speakers, various accents)

* **LJSpeech**: High-quality single-speaker English (via Tacotron2)

## License

MIT License. See [LICENSE](https://LICENSE) for details.

- - -

> **Warning**\
> This is a work in progress. Error handling is minimal, and results may vary with complex Markdown.
