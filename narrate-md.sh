#!/bin/bash
# Script: narrate-md.sh
# Author: Nick Pepin
# Date: 2025-04
#
# WARNING: This script is a work in progress, contains minimal error handling, and may not function as intended.
# ----------------------------------------------------------------------------------------------------------------
#
# This script converts a markdown file into an audio file using Text-to-Speech (TTS) and Docker.
#
# It performs the following steps:
# 1. Cleans the input markdown file.
# 2. Splits the markdown content into manageable chunks if necessary.
# 3. Generates audio for each chunk using TTS.
# 4. Merges the generated audio chunks into a single final audio file.
#
# Usage:
#   ./narrate-md.sh [-p] <input.md>
#
# Options:
#   -p            Play the generated audio file after processing.
#   <input.md>    The input markdown file to be converted into audio.
#
# Prerequisites:
#   - Host Filesystem: Assumes $HOME/Projects/TTS/ is available as the working directory with all pulled files.
#   - Docker: Ensure Docker is installed and running.
#   - Docker Compose: Required for managing the TTS container. Version provided enables GPU support.
#   - ffmpeg: Used for audio processing and merging.
#   - mp3wrap: Utility for combining multiple MP3 files.
#   - str: A string manipulation tool (if used in the script).
#
# VCTK Model and Coqui-TTS
# ----------------------------------------------------------------------------------------------------------------
# VCTK Model:
#   - The VCTK model is a pre-trained Text-to-Speech (TTS) model designed for high-quality speech synthesis.
#   - It is based on the VCTK dataset, which contains recordings of multiple speakers with various accents.
#   - The model supports speaker-specific synthesis by using speaker IDs (e.g., "p230") to generate speech in different voices.
#   - The model is compatible with Coqui-TTS, a flexible and open-source TTS framework.
#
# Coqui-TTS:
#   - Coqui-TTS is an open-source Text-to-Speech framework that supports training and inference of TTS models.
#   - It provides a wide range of pre-trained models, including VCTK, LJSpeech, and others.
#   - Coqui-TTS supports advanced features such as multi-speaker synthesis, vocoders, and GPU acceleration.
#   - The framework is designed to be modular and extensible, making it suitable for research and production use cases.
#   - In this script, Coqui-TTS is used within a Docker container to generate audio files from text input.

# Paramaters
MAX_LINES_PER_CHUNK=20 # Maximum lines per chunk of the markdown file
MODEL="tts_models/en/vctk/vits" # VCTK model
SPEAKER="p230" # VCTK speaker ID
CONTAINER="coqui-tts" # Docker container name
# MODEL="tts_models/en/ljspeech/tacotron2-DDC_ph"
# VOCODER="vocoder_models/en/ljspeech/univnet"

return_dir="$pwd"
app_dir="$HOME/Projects/TTS"
INPUT_MD="$1"

# If no arguments provided, show usage
[ -z "$INPUT_MD" ] && {
    echo "Converts a markdown file to an audio file using TTS and Docker. The MP3 file is created in the current directory."
    echo "Usage: $0 [-p] <input.md>"
    echo "Where:"
    echo "  <input.md>  The input markdown file to be converted to audio"
    echo "  -p          (Optional) play the audio file after generation"
    exit 1
}

# Check for command line switches
PLAY=false
while true; do
    case "$1" in
    -p)
        shift
        INPUT_MD="$1"
        PLAY=true
        break
        ;;
    --)
        shift
        break
        ;;
    *) break ;;
    esac
done

[ ! -f "$INPUT_MD" ] && {
    echo "Error: File $INPUT_MD not found"
    exit 1
}

# get base filename without path or extension
orig_base="${INPUT_MD##*/}"
orig_base="${orig_base%.*}"
INPUT_MD="$(realpath "$INPUT_MD")"

cd "$app_dir" >/dev/null 2>&1 || {
    echo "Error: Failed to change directory to $app_dir"
    exit 1
}

# Create subdirectories if they don't exist
mkdir -p input output logs models >/dev/null 2>&1
# TODO: make the container use the models/ bindmount to avoid redundant downloads

# Check if the Docker container exists
container_exists=$(docker container inspect $CONTAINER 2>/dev/null)
if [ "$container_exists" = "[]" ]; then
    echo "Docker container '$CONTAINER' not found. Creating the container..."
    docker-compose up -d
    sleep 2
    # docker exec -it $CONTAINER python3 -c "from TTS.utils.manage import ModelManager; ModelManager().download_model('$MODEL'); ModelManager().download_model('$VOCODER')"
    docker exec -it $CONTAINER python3 -c "from TTS.utils.manage import ModelManager; ModelManager().download_model('$MODEL')"
    sleep 2
else
    echo "Docker container '$CONTAINER' found."
fi

# check if docker container is running
container_running=$(docker ps | grep -i "$CONTAINER")
if [ -z "$container_running" ]; then
    echo "Docker container '$CONTAINER' is not running. Starting the container..."
    docker container start $CONTAINER
    sleep 2
else
    echo "Docker container '$CONTAINER' is running."
fi

#####################################################################
# FUNCTIONS
#####################################################################

# Function: md_to_text
# ------------------------------------
# This function processes a chunk of the markdown file to convert it into plain text 
# using a Python script embedded within the shell script.
#
# Parameters:
#   $1 - Input Markdown file path
#   $2 - Output plain text file path
#
# Description:
#   - The function reads the input Markdown file and applies a series of regex-based
#     transformations to clean and extract plain text content.
#   - The transformations include:
#       - Removing HTML comments, tags, and excessive newlines.
#       - Stripping Markdown syntax such as headings, links, bold/italic formatting,
#         inline code, code blocks, and list markers.
#       - Removing images and trailing whitespace.
#   - The cleaned text is written to the specified output file.
#
# Usage:
#   md_to_text <input_markdown_file> <output_text_file>
#
# Notes:
#   - The function uses Python 3 for text processing.
#   - Ensure that the input file exists and is readable.
#   - The output file will be overwritten if it already exists.
#
md_to_text() {
    python3 - "$1" <<'PYTHON_EOF' >"$2"
import re
import sys

if len(sys.argv) < 2:
    print("Error: No input file specified", file=sys.stderr)
    sys.exit(1)

input_file = sys.argv[1]

try:
    with open(input_file, 'r', encoding='utf-8') as f:
        text = f.read()

    # Multi-step cleaning pipeline
    patterns = [
        (r'<!--.*?-->', ''),                          # HTML comments
        (r'#{1,6}\s*', ''),                           # Headings
        (r'\[([^\]]+)\]\([^\)]+\)', r'\1'),           # Links
        (r'\*{1,2}(.*?)\*{1,2}', r'\1'),              # Bold/italic
        (r'_{1,2}(.*?)_{1,2}', r'\1'),                # Underline/italic
        (r'```.*?```', '', re.DOTALL),                # Code blocks
        (r'`([^`]+)`', r'\1'),                        # Inline code
        (r'^\s*[-*+]\s*', '', re.MULTILINE),          # List markers
        (r'^\s*[0-9]+\.\s*', '', re.MULTILINE),       # Numbered lists
        (r'!\[.*?\]\(.*?\)', ''),                    # Images
        (r'<[^>]+>', ''),                             # HTML tags
        (r'\n{3,}', '\n\n'),                          # Excessive newlines
        (r'[ \t]+\n', '\n')                           # Trailing whitespace
    ]

    for pattern, replacement, *flags in patterns:
        flags = flags[0] if flags else 0
        text = re.sub(pattern, replacement, text, flags=flags)

    # Final cleanup
    text = text.strip()
    sys.stdout.write(text)

except Exception as e:
    print(f"Error processing Markdown: {str(e)}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
}

# Function: clean_markdown
# ------------------------------------
# Performs additional cleaning steps on markdown input to improve suitability for narration. 
# The function takes two arguments: the input markdown file path ($1) and the output file path ($2). 
# TODO: find a better way to insert pauses
#
# The steps performed by the function include:
#
# 1. Invoking a Python script `md_to_text` to process the input markdown file ($1) and
#    save the initial cleaned output to the specified output file ($2).
# 2. Using string replacement commands (`str replace`) to:
#    - Replace ". " with ".. ".
#    - Replace "," with ",,".
#    - Replace "; " with ";, ".
#    - Replace ": " with ":, ".
#    - Add commas around parentheses and replace "/" with ",,".
#    - Ensure "e.g." is followed by a comma ("e.g.,").
# 3. Using `sed` to replace newline characters with a pattern of newline followed by "....".
#
clean_markdown() {
    # Clean markdown using Python script
    md_to_text "$1" "$2"
    # echo "Cleaning $1 to $2..."
    temp_file=$(mktemp)
    cat "$2" | str replace ". " ".. " | str replace "," ",," >$temp_file
    cat "$temp_file" | str replace "; " ";, " | str replace ": " ":, " | str replace "(" ",(" | str replace ")" ")," | str replace "/" ",," | str replace "e.g." "e.g.," >"$2"
    cat "$2" | sed ':a;N;$!ba;s/\n/\n..../g' >$temp_file
    mv $temp_file "$2" >/dev/null 2>&1
}

# Function: generate_audio
# ------------------------------------
# This function generate an audio file from the chunked text input using a Docker TTS (Text-to-Speech)
# container and converts the output to MP3 format.
#
# Parameters:
#   $1 - Path to the input text file containing the text to be converted to audio.
#   $2 - Base path for the output audio files (without extension).
#
# Functionality:
#   1. Extracts the base name and constructs paths for WAV and MP3 files.
#   2. Uses a Docker container to generate a WAV audio file from the input text.
#      - The TTS model, speaker index, and CUDA usage are configurable via environment variables:
#        - $CONTAINER: Name of the Docker container running the TTS service.
#        - $MODEL: Name of the TTS model to use.
#        - $SPEAKER: Speaker index for voice selection.
#      - The generated WAV file is stored in the Docker container's `/output` directory.
#   3. Converts the generated WAV file to an MP3 file using `ffmpeg`.
#      - Applies an audio filter to adjust playback speed (tempo).
#   4. Cleans up temporary files:
#
# Notes:
#   - The `ffmpeg` command is configured to adjust the tempo of the audio.
#   - Ensure the required environment variables ($CONTAINER, $MODEL, $SPEAKER) are set before running the script.
#   - The function assumes that the Docker container is already running and accessible.
# TODO: Error handling is minimal; consider adding checks for successful execution of commands.
#
generate_audio() {
    local base="$2"
    local wave_file="${base}.wav"
    local mp3_file="${base}.mp3"
    local base_docker="${base##*/}"
    local docker_out="/output/$base_docker.wav"

    echo "Generating $mp3_file"

    # Generate audio using Docker TTS container
    docker exec -i $CONTAINER \
        tts --text "$(cat "$1")" \
        --model_name "$MODEL" \
        --out_path "$docker_out" \
        --speaker_idx "$SPEAKER" \
        --use_cuda true >/dev/null 2>&1
    # --vocoder_name "$VOCODER" \

    # Convert the generated WAV file to MP3
    # ffmpeg -i "$wave_file" -filter:a "rubberband=pitch=1.059463094352953, rubberband=tempo=.80" -acodec copy "$mp3_file" >/dev/null 2>&1
    ffmpeg -i "$wave_file" -filter:a atempo=.78 "$mp3_file" >/dev/null 2>&1
    rm -f "$wave_file" >/dev/null 2>&1
    rm -f "$1" >/dev/null 2>&1
}

# Overall process flow
process() {
    local file="$1"
    local file_base="${file##*/}"
    file_base="${file_base%.*}"
    # echo "Processing $file_base..."

    # clean the markdown and generate audio for each part
    local cleaned_txt="output/$file_base.txt"

    # Clean the markdown file
    clean_markdown "$file" "$cleaned_txt"

    # Generate audio file
    local base_audio_fn="output/$file_base"
    generate_audio "$cleaned_txt" "$base_audio_fn"
}

#####################################################################
# MAINLINE
#####################################################################

echo "Processing $INPUT_MD..."

# Check if the file has more than MAX_LINES_PER_CHUNK lines
line_count=$(wc -l <"$INPUT_MD")
if [ "$line_count" -le $MAX_LINES_PER_CHUNK ]; then

    # If the file doesn't need splitting, process it directly
    process "$INPUT_MD"
else

    # Split the file into parts
    rm "input/$orig_base-part-*" >/dev/null 2>&1
    split -l $MAX_LINES_PER_CHUNK -d --suffix-length=5 "$INPUT_MD" "input/$orig_base-part-"

    rm -f "output/$orig_base-part-"*.mp3 >/dev/null 2>&1
    rm -f "output/$orig_base-part-"*.wav >/dev/null 2>&1

    # Iterate through the files to process each chunk
    for file in input/$orig_base-part-*; do
        # echo "Performing TTS on chunk $file..."
        process "$file"
    done

    # Merge the audio chunks into one MP3 file
    mp3_files=$(ls "output/$orig_base-part-"*.mp3 2>/dev/null | tr '\n' ' ')
    echo "Merging audio chunks into one MP3 file."
    cmd="/usr/bin/mp3wrap output/$orig_base.mp3 $mp3_files"
    eval "$cmd" >/dev/null 2>&1
    cmd="mv -f output/${orig_base}_MP3WRAP.mp3 output/$orig_base.mp3"
    eval "$cmd" >/dev/null 2>&1
    echo "Final audio file: $orig_base.mp3"
    rm -f "output/$orig_base-part-"*.mp3 >/dev/null 2>&1
    rm -f "output/$orig_base-part-"*.wav >/dev/null 2>&1
    rm -f "input/$orig_base-part-"* >/dev/null 2>&1

fi

# Return to the original directory
cd "$return_dir" >/dev/null 2>&1 

# Move the final audio file to the original directory
mv -f "$app_dir/output/$orig_base.mp3" . >/dev/null 2>&1

# Stop the Docker container
echo "Stopping Docker container '$CONTAINER'..."
docker container stop $CONTAINER >/dev/null 2>&1

# Play the final audio file if requested with '-p'
echo "Playing the final audio file..."
if [ $PLAY = true ]; then
    ffplay -v 0 -nodisp -autoexit "$orig_base.mp3"
fi

echo "Done."
