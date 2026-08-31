#!/usr/bin/env bash

# Interactive Linux tool for creating email-sized split ZIP archives.

set -Eeuo pipefail

CHUNK_SIZE_MB="${CHUNK_SIZE_MB:-15}"

COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'

SEVENZIP_BIN=""
GUI_TOOL=""
OUTPUT_DIR=""
NORMALIZED_PATH=""
ARCHIVE_PATH=""
SELECTED_FILES=()
CREATED_PARTS=()

log_info() {
    printf '%b[INFO]%b %s\n' "$COLOR_CYAN" "$COLOR_RESET" "$*"
}

log_success() {
    printf '%b[✓]%b %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

log_error() {
    printf '%b[✗]%b %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

log_warning() {
    printf '%b[!]%b %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*"
}

print_header() {
    printf '\n%b==================================================%b\n' "$COLOR_CYAN" "$COLOR_RESET"
    printf '%b%s%b\n' "$COLOR_CYAN" "$*" "$COLOR_RESET"
    printf '%b==================================================%b\n\n' "$COLOR_CYAN" "$COLOR_RESET"
}

find_7z() {
    local candidate

    for candidate in 7z 7zz 7za; do
        if command -v "$candidate" >/dev/null 2>&1; then
            SEVENZIP_BIN="$candidate"
            return 0
        fi
    done

    log_error "7-Zip is not installed."
    printf '\nInstallation on current Ubuntu releases:\n'
    printf '  sudo apt install 7zip\n'
    printf '\nOlder distributions may provide p7zip-full instead.\n'
    return 1
}

detect_gui_tool() {
    if command -v zenity >/dev/null 2>&1; then
        GUI_TOOL="zenity"
    elif command -v kdialog >/dev/null 2>&1; then
        GUI_TOOL="kdialog"
    else
        GUI_TOOL=""
    fi
}

# Safely handles paths entered as ~, ~/path, or with one pair of wrapping quotes.
# The result is returned through NORMALIZED_PATH so prompts cannot be captured as data.
normalize_user_path() {
    local value="$1"
    local length=${#value}

    if (( length >= 2 )); then
        if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
            value="${value:1:length-2}"
        elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
            value="${value:1:length-2}"
        fi
    fi

    case "$value" in
        '~')
            value="$HOME"
            ;;
        '~/'*)
            value="$HOME/${value:2}"
            ;;
    esac

    NORMALIZED_PATH="$value"
}

select_files_gui() {
    local selection=""
    local file_path

    case "$GUI_TOOL" in
        zenity)
            selection=$(zenity --file-selection --multiple --separator=$'\n' \
                --title="Select files to zip and split" 2>/dev/null) || return 1
            ;;
        kdialog)
            selection=$(kdialog --getopenfilename "$HOME" "*" --multiple \
                --separate-output --title "Select files to zip and split" 2>/dev/null) || return 1
            ;;
        *)
            return 1
            ;;
    esac

    while IFS= read -r file_path; do
        [[ -z "$file_path" ]] && continue
        if [[ -f "$file_path" ]]; then
            SELECTED_FILES+=("$file_path")
        else
            log_warning "Ignoring unavailable file: $file_path"
        fi
    done <<< "$selection"

    (( ${#SELECTED_FILES[@]} > 0 ))
}

select_files_terminal() {
    local file_path
    local counter=1

    log_info "Enter file paths (one per line, press Enter on an empty line when done):"
    printf '\n'

    while true; do
        if ! IFS= read -r -p "File $counter: " file_path; then
            printf '\n'
            break
        fi

        if [[ -z "$file_path" ]]; then
            if (( ${#SELECTED_FILES[@]} > 0 )); then
                break
            fi
            log_error "Please enter at least one file path."
            continue
        fi

        normalize_user_path "$file_path"
        file_path="$NORMALIZED_PATH"

        if [[ -f "$file_path" ]]; then
            SELECTED_FILES+=("$file_path")
            ((counter += 1))
        else
            log_error "File not found: $file_path"
        fi
    done

    (( ${#SELECTED_FILES[@]} > 0 ))
}

select_output_directory_gui() {
    local selection=""

    case "$GUI_TOOL" in
        zenity)
            selection=$(zenity --file-selection --directory \
                --title="Select output directory for split archive" 2>/dev/null) || return 1
            ;;
        kdialog)
            selection=$(kdialog --getexistingdirectory "$HOME" \
                --title "Select output directory for split archive" 2>/dev/null) || return 1
            ;;
        *)
            return 1
            ;;
    esac

    [[ -n "$selection" ]] || return 1
    OUTPUT_DIR="$selection"
}

select_output_directory_terminal() {
    local dir_path

    log_info "Enter output directory path (default: current directory):"
    IFS= read -r -p "> " dir_path || return 1

    if [[ -z "$dir_path" ]]; then
        dir_path="."
    fi

    normalize_user_path "$dir_path"
    OUTPUT_DIR="$NORMALIZED_PATH"
}

prepare_output_directory() {
    if [[ -e "$OUTPUT_DIR" && ! -d "$OUTPUT_DIR" ]]; then
        log_error "Output path is not a directory: $OUTPUT_DIR"
        return 1
    fi

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_info "Creating output directory: $OUTPUT_DIR"
        if ! mkdir -p -- "$OUTPUT_DIR"; then
            log_error "Failed to create output directory: $OUTPUT_DIR"
            return 1
        fi
    fi

    if [[ ! -w "$OUTPUT_DIR" ]]; then
        log_error "Output directory is not writable: $OUTPUT_DIR"
        return 1
    fi
}

choose_archive_path() {
    local timestamp
    local archive_stem
    local suffix=1

    timestamp=$(date +%Y%m%d_%H%M%S)
    archive_stem="archive_$timestamp"
    ARCHIVE_PATH="$OUTPUT_DIR/$archive_stem.zip"

    while [[ -e "$ARCHIVE_PATH" || -e "$ARCHIVE_PATH.001" ]]; do
        ARCHIVE_PATH="$OUTPUT_DIR/${archive_stem}_$suffix.zip"
        ((suffix += 1))
    done
}

collect_created_parts() {
    local candidate
    local suffix
    local candidates=()

    CREATED_PARTS=()
    shopt -s nullglob
    candidates=("$ARCHIVE_PATH".[0-9]*)
    shopt -u nullglob

    for candidate in "${candidates[@]}"; do
        suffix="${candidate##*.}"
        if [[ "$suffix" =~ ^[0-9]{3,}$ ]]; then
            CREATED_PARTS+=("$candidate")
        fi
    done
}

human_size() {
    local file_path="$1"
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$(stat -c '%s' -- "$file_path")"
    else
        du -h -- "$file_path" | awk '{print $1}'
    fi
}

create_and_split_archive() {
    local part_file

    choose_archive_path

    log_info "Creating ZIP archive with automatic splitting..."
    log_info "Archive name: $(basename -- "$ARCHIVE_PATH")"
    log_info "Chunk size: ${CHUNK_SIZE_MB} MiB"
    printf '\n'

    if ! "$SEVENZIP_BIN" a -tzip "-v${CHUNK_SIZE_MB}m" \
        "$ARCHIVE_PATH" -- "${SELECTED_FILES[@]}"; then
        log_error "7-Zip failed to create the archive."
        return 1
    fi

    collect_created_parts
    if (( ${#CREATED_PARTS[@]} == 0 )); then
        log_error "7-Zip finished, but no .zip.001 volume was found."
        return 1
    fi

    printf '\n'
    log_success "Archive created successfully."
    for part_file in "${CREATED_PARTS[@]}"; do
        log_success "$(basename -- "$part_file") ($(human_size "$part_file"))"
    done
}

show_summary() {
    local first_part="${CREATED_PARTS[0]}"

    print_header "OPERATION COMPLETE"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Total volumes: ${#CREATED_PARTS[@]}"
    printf '\n%bTo extract on another computer:%b\n' "$COLOR_BOLD" "$COLOR_RESET"
    printf '  1. Keep every .zip.### file in the same directory.\n'
    printf '  2. Open %s with 7-Zip.\n' "$(basename -- "$first_part")"
    printf '  3. Or run: ./merge-zip-files.sh\n\n'
}

main() {
    if [[ ! "$CHUNK_SIZE_MB" =~ ^[1-9][0-9]*$ ]]; then
        log_error "CHUNK_SIZE_MB must be a positive integer: $CHUNK_SIZE_MB"
        exit 1
    fi

    print_header "7-Zip Auto Split for Email (Linux)"
    find_7z || exit 1
    detect_gui_tool

    if [[ -n "$GUI_TOOL" ]]; then
        log_info "Opening file selection dialog with $GUI_TOOL..."
        if ! select_files_gui; then
            log_warning "GUI selection was cancelled or failed; switching to terminal mode."
            SELECTED_FILES=()
            select_files_terminal || exit 1
        fi
    else
        select_files_terminal || exit 1
    fi

    printf '\n'
    log_success "Selected files:"
    printf '  • %s\n' "${SELECTED_FILES[@]}"
    printf '\n'

    if [[ -n "$GUI_TOOL" ]]; then
        log_info "Opening output directory dialog..."
        if ! select_output_directory_gui; then
            log_warning "GUI selection was cancelled or failed; switching to terminal mode."
            select_output_directory_terminal || exit 1
        fi
    else
        select_output_directory_terminal || exit 1
    fi

    prepare_output_directory || exit 1
    printf '\n'

    if create_and_split_archive; then
        show_summary
    else
        exit 1
    fi
}

main "$@"
