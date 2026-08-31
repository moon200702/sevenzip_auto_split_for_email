#!/usr/bin/env bash

# Interactive Linux tool for validating, extracting, or combining split ZIP archives.

set -Eeuo pipefail

COLOR_CYAN='\033[0;36m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

SEVENZIP_BIN=""
GUI_TOOL=""
NORMALIZED_PATH=""
INPUT_DIR=""
FIRST_PART=""
ARCHIVE_PATH=""
ARCHIVE_FILE=""
BASE_NAME=""
FIRST_PARTS=()
VOLUME_PARTS=()

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

    log_error "7-Zip is required to verify and extract split archives."
    printf '\nInstall it with:\n  sudo apt install 7zip\n'
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

select_input_directory_gui() {
    local selection=""

    case "$GUI_TOOL" in
        zenity)
            selection=$(zenity --file-selection --directory \
                --title="Select the directory containing split ZIP files" 2>/dev/null) || return 1
            ;;
        kdialog)
            selection=$(kdialog --getexistingdirectory "$HOME" \
                --title "Select the directory containing split ZIP files" 2>/dev/null) || return 1
            ;;
        *)
            return 1
            ;;
    esac

    [[ -n "$selection" ]] || return 1
    INPUT_DIR="$selection"
}

select_input_directory_terminal() {
    local dir_path

    log_info "Enter directory containing .zip.001 files (default: current directory):"
    IFS= read -r -p "> " dir_path || return 1
    [[ -z "$dir_path" ]] && dir_path="."

    normalize_user_path "$dir_path"
    INPUT_DIR="$NORMALIZED_PATH"
}

validate_input_directory() {
    if [[ ! -d "$INPUT_DIR" ]]; then
        log_error "Directory not found: $INPUT_DIR"
        return 1
    fi
}

find_first_parts() {
    shopt -s nullglob
    FIRST_PARTS=("$INPUT_DIR"/*.zip.001)
    shopt -u nullglob

    if (( ${#FIRST_PARTS[@]} == 0 )); then
        log_error "No .zip.001 files found in: $INPUT_DIR"
        log_info "Expected names such as archive_20260831_102251.zip.001"
        return 1
    fi
}

choose_archive() {
    local choice
    local index

    if (( ${#FIRST_PARTS[@]} == 1 )); then
        FIRST_PART="${FIRST_PARTS[0]}"
        return 0
    fi

    log_info "Multiple split archives were found:"
    for index in "${!FIRST_PARTS[@]}"; do
        printf '  %d. %s\n' "$((index + 1))" "$(basename -- "${FIRST_PARTS[index]}")"
    done

    while true; do
        IFS= read -r -p "Choose an archive [1-${#FIRST_PARTS[@]}]: " choice || return 1
        if [[ "$choice" =~ ^[0-9]+$ ]] &&
            (( choice >= 1 && choice <= ${#FIRST_PARTS[@]} )); then
            FIRST_PART="${FIRST_PARTS[choice - 1]}"
            return 0
        fi
        log_error "Invalid selection: $choice"
    done
}

collect_volume_parts() {
    local candidate
    local suffix
    local part_number
    local expected=1
    local candidates=()

    ARCHIVE_PATH="${FIRST_PART%.001}"
    ARCHIVE_FILE=$(basename -- "$ARCHIVE_PATH")
    BASE_NAME="${ARCHIVE_FILE%.zip}"

    shopt -s nullglob
    candidates=("$ARCHIVE_PATH".[0-9]*)
    shopt -u nullglob

    VOLUME_PARTS=()
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] && VOLUME_PARTS+=("$candidate")
    done < <(printf '%s\n' "${candidates[@]}" | sort -V)

    if (( ${#VOLUME_PARTS[@]} == 0 )); then
        log_error "No volumes found for: $ARCHIVE_FILE"
        return 1
    fi

    for candidate in "${VOLUME_PARTS[@]}"; do
        suffix="${candidate##*.}"
        if [[ ! "$suffix" =~ ^[0-9]{3,}$ ]]; then
            log_error "Unexpected volume filename: $(basename -- "$candidate")"
            return 1
        fi

        part_number=$((10#$suffix))
        if (( part_number != expected )); then
            log_error "Missing volume $(printf '%03d' "$expected") before $(basename -- "$candidate")"
            return 1
        fi
        ((expected += 1))
    done
}

show_volume_summary() {
    local part_file

    log_success "Selected archive: $ARCHIVE_FILE"
    log_info "Volumes found: ${#VOLUME_PARTS[@]}"
    for part_file in "${VOLUME_PARTS[@]}"; do
        printf '  • %s\n' "$(basename -- "$part_file")"
    done
    printf '\n'
}

test_archive() {
    log_info "Testing all volumes with 7-Zip..."
    printf '\n'

    if ! "$SEVENZIP_BIN" t "$FIRST_PART"; then
        printf '\n'
        log_error "Archive verification failed. A volume may be missing or corrupted."
        return 1
    fi

    printf '\n'
    log_success "Archive verification passed."
}

directory_has_contents() {
    [[ -d "$1" ]] && [[ -n "$(find "$1" -mindepth 1 -print -quit 2>/dev/null)" ]]
}

extract_archive() {
    local extract_dir
    local response

    log_info "Enter extraction directory (default: $INPUT_DIR/${BASE_NAME}_extracted):"
    IFS= read -r -p "> " extract_dir || return 1
    [[ -z "$extract_dir" ]] && extract_dir="$INPUT_DIR/${BASE_NAME}_extracted"
    normalize_user_path "$extract_dir"
    extract_dir="$NORMALIZED_PATH"

    if [[ -e "$extract_dir" && ! -d "$extract_dir" ]]; then
        log_error "Extraction path is not a directory: $extract_dir"
        return 1
    fi

    if directory_has_contents "$extract_dir"; then
        log_warning "Extraction directory is not empty: $extract_dir"
        IFS= read -r -p "Overwrite files with matching names? (y/N): " response || return 1
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Extraction cancelled."
            return 0
        fi
    fi

    mkdir -p -- "$extract_dir"
    printf '\n'
    log_info "Extracting files..."
    if ! "$SEVENZIP_BIN" x "$FIRST_PART" "-o$extract_dir" -aoa -y; then
        log_error "Extraction failed."
        return 1
    fi

    printf '\n'
    log_success "Files extracted to: $extract_dir"
}

combine_archive() {
    local output_path
    local response
    local temp_file

    log_info "Enter combined ZIP path (default: $ARCHIVE_PATH):"
    IFS= read -r -p "> " output_path || return 1
    [[ -z "$output_path" ]] && output_path="$ARCHIVE_PATH"
    normalize_user_path "$output_path"
    output_path="$NORMALIZED_PATH"
    [[ "$output_path" == *.zip ]] || output_path="${output_path}.zip"

    if [[ -e "$output_path" ]]; then
        log_warning "File already exists: $output_path"
        IFS= read -r -p "Overwrite it? (y/N): " response || return 1
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Combine cancelled."
            return 0
        fi
    fi

    if [[ ! -d "$(dirname -- "$output_path")" ]]; then
        log_error "Output directory does not exist: $(dirname -- "$output_path")"
        return 1
    fi

    temp_file=$(mktemp --tmpdir="$(dirname -- "$output_path")" ".combined-zip.XXXXXX")
    if ! cat -- "${VOLUME_PARTS[@]}" > "$temp_file"; then
        rm -f -- "$temp_file"
        log_error "Failed to combine volumes."
        return 1
    fi

    log_info "Testing the combined ZIP before saving it..."
    if ! "$SEVENZIP_BIN" t "$temp_file" >/dev/null; then
        rm -f -- "$temp_file"
        log_error "Combined ZIP verification failed."
        return 1
    fi

    if ! mv -f -- "$temp_file" "$output_path"; then
        rm -f -- "$temp_file"
        log_error "Failed to save combined ZIP: $output_path"
        return 1
    fi

    log_success "Combined ZIP saved to: $output_path"
}

choose_action() {
    local action

    printf '\nChoose an action:\n'
    printf '  1. Extract files (recommended)\n'
    printf '  2. Combine volumes into one ZIP\n'
    printf '  3. Test only\n'
    IFS= read -r -p "Selection [1]: " action || return 1
    [[ -z "$action" ]] && action=1

    case "$action" in
        1) extract_archive ;;
        2) combine_archive ;;
        3) log_info "Test complete; no files were changed." ;;
        *)
            log_error "Invalid action: $action"
            return 1
            ;;
    esac
}

main() {
    print_header "Split ZIP Archive Tool (Linux)"
    find_7z || exit 1
    detect_gui_tool

    if (( $# > 0 )); then
        normalize_user_path "$1"
        INPUT_DIR="$NORMALIZED_PATH"
    elif [[ -n "$GUI_TOOL" ]]; then
        log_info "Opening directory selection dialog with $GUI_TOOL..."
        if ! select_input_directory_gui; then
            log_warning "GUI selection was cancelled or failed; switching to terminal mode."
            select_input_directory_terminal || exit 1
        fi
    else
        select_input_directory_terminal || exit 1
    fi

    validate_input_directory || exit 1
    find_first_parts || exit 1
    choose_archive || exit 1
    collect_volume_parts || exit 1

    printf '\n'
    show_volume_summary
    test_archive || exit 1
    choose_action || exit 1

    printf '\n'
    log_info "Done."
}

main "$@"
