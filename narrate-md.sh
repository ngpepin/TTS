#!/bin/bash
# This script converts a markdown file to an audio file using TTS and Docker.
# It cleans the markdown file, splits it into chunks if necessary, and generates audio for each chunk.
# It also merges the audio chunks into one final audio file.
#
# Usage: ./narrate-md.sh [-p] <input.md>
#
# Options:
# -p: Play the audio file after generation
# <input.md>: The input markdown file to be converted to audio
#
# Requirements:
# - Docker
# - Docker Compose
# - ffmpeg
# - mp3wrap
# - str (

MAX_LINES_PER_CHUNK=20
MODEL="tts_models/en/vctk/vits"
# MODEL="tts_models/en/ljspeech/tacotron2-DDC_ph"
# VOCODER="vocoder_models/en/ljspeech/univnet"
SPEAKER="p230" # VCTK speaker ID
CONTAINER="coqui-tts"

return_dir="$pwd"
app_dir="$HOME/Projects/TTS"

# Input/Output config
INPUT_MD="$1"
[ -z "$INPUT_MD" ] && {
    echo "Converts a markdown file to an audio file using TTS and Docker. The MP3 file is created in the current directory."
    echo "Usage: $0 [-p] <input.md>"
    echo "Where:"
    echo "  <input.md>  The input markdown file to be converted to audio"
    echo "  -p          (Optional) play the audio file after generation"
    exit 1
}

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
mkdir -p input output >/dev/null 2>&1

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

#################################

# Step 1: Clean markdown using Python
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

# Step 2: Generate TTS via Docker
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

#######################

echo "Processing $INPUT_MD..."

# check if the file has more than MAX_LINES_PER_CHUNK lines
line_count=$(wc -l <"$INPUT_MD")
if [ "$line_count" -le $MAX_LINES_PER_CHUNK ]; then

    # if the file doesn't need splitting, process it directly
    process "$INPUT_MD"
    if [ $PLAY = true ]; then
        # Play the audio file
        ffplay -v 0 -nodisp -autoexit "output/$orig_base.mp3"
    fi
else

    # split the file into parts
    rm "input/$orig_base-part-*" >/dev/null 2>&1
    split -l $MAX_LINES_PER_CHUNK -d --suffix-length=5 "$INPUT_MD" "input/$orig_base-part-"

    rm -f "output/$orig_base-part-"*.mp3 >/dev/null 2>&1
    rm -f "output/$orig_base-part-"*.wav >/dev/null 2>&1

    # iterate through the files
    for file in input/$orig_base-part-*; do
        # echo "Performing TTS on chunk $file..."
        process "$file"
    done

    # merge the audio files
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

    if [ $PLAY = true ]; then
        # Play the audio file
        ffplay -v 0 -nodisp -autoexit "output/$orig_base.mp3"
    fi
fi

cd "$return_dir" >/dev/null 2>&1 || {
    echo "Error: Failed to change directory back to $return_dir"
}
mv -f "$return_dir/output/$orig_base.mp3" . >/dev/null 2>&1
docker container stop $CONTAINER >/dev/null 2>&1
