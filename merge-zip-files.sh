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
DESTINATION_DIR=""
ACTION=""
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

select_first_part_gui() {
    local selection=""

    case "$GUI_TOOL" in
        zenity)
            selection=$(zenity --file-selection \
                --title="Select the first split ZIP volume (.zip.001)" \
                --file-filter="Split ZIP first volume (*.zip.001) | *.zip.001" \
                --file-filter="All files | *" 2>/dev/null) || return 1
            ;;
        kdialog)
            selection=$(kdialog --getopenfilename "$HOME" \
                "*.zip.001|Split ZIP first volume" \
                --title "Select the first split ZIP volume" 2>/dev/null) || return 1
            ;;
        *)
            return 1
            ;;
    esac

    [[ -n "$selection" ]] || return 1
    FIRST_PART="$selection"
}

select_first_part_terminal() {
    local file_path

    log_info "Enter the path to the first split ZIP volume (.zip.001):"
    IFS= read -r -p "> " file_path || return 1
    [[ -n "$file_path" ]] || return 1

    normalize_user_path "$file_path"
    FIRST_PART="$NORMALIZED_PATH"
}

validate_first_part() {
    if [[ ! -f "$FIRST_PART" ]]; then
        log_error "File not found: $FIRST_PART"
        return 1
    fi

    if [[ "$FIRST_PART" != *.zip.001 ]]; then
        log_error "Please select the first volume ending in .zip.001"
        return 1
    fi

    INPUT_DIR=$(dirname -- "$FIRST_PART")
}

select_destination_directory_gui() {
    local title="$1"
    local selection=""

    case "$GUI_TOOL" in
        zenity)
            selection=$(zenity --file-selection --directory \
                --filename="$INPUT_DIR/" --title="$title" 2>/dev/null) || return 1
            ;;
        kdialog)
            selection=$(kdialog --getexistingdirectory "$INPUT_DIR" \
                --title "$title" 2>/dev/null) || return 1
            ;;
        *)
            return 1
            ;;
    esac

    [[ -n "$selection" ]] || return 1
    DESTINATION_DIR="$selection"
}

select_destination_directory_terminal() {
    local title="$1"
    local dir_path

    log_info "$title (default: $INPUT_DIR):"
    IFS= read -r -p "> " dir_path || return 1
    [[ -z "$dir_path" ]] && dir_path="$INPUT_DIR"

    normalize_user_path "$dir_path"
    DESTINATION_DIR="$NORMALIZED_PATH"
}

select_destination_directory() {
    local title="$1"

    if [[ -n "$GUI_TOOL" ]]; then
        log_info "Opening output directory dialog with $GUI_TOOL..."
        if ! select_destination_directory_gui "$title"; then
            log_warning "GUI selection was cancelled or failed; switching to terminal mode."
            select_destination_directory_terminal "$title" || return 1
        fi
    else
        select_destination_directory_terminal "$title" || return 1
    fi

    if [[ -e "$DESTINATION_DIR" && ! -d "$DESTINATION_DIR" ]]; then
        log_error "Output path is not a directory: $DESTINATION_DIR"
        return 1
    fi

    if [[ ! -d "$DESTINATION_DIR" ]]; then
        log_info "Creating output directory: $DESTINATION_DIR"
        mkdir -p -- "$DESTINATION_DIR" || return 1
    fi

    if [[ ! -w "$DESTINATION_DIR" ]]; then
        log_error "Output directory is not writable: $DESTINATION_DIR"
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

    select_destination_directory "Select output directory for extracted files" || return 1
    extract_dir="$DESTINATION_DIR/${BASE_NAME}_extracted"

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

    select_destination_directory "Select output directory for the combined ZIP" || return 1
    output_path="$DESTINATION_DIR/$ARCHIVE_FILE"

    if [[ -e "$output_path" ]]; then
        log_warning "File already exists: $output_path"
        IFS= read -r -p "Overwrite it? (y/N): " response || return 1
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Combine cancelled."
            return 0
        fi
    fi

    temp_file=$(mktemp --tmpdir="$DESTINATION_DIR" ".combined-zip.XXXXXX")
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

choose_action_gui() {
    local selection=""

    case "$GUI_TOOL" in
        zenity)
            selection=$(zenity --list --radiolist \
                --title="Choose an action" \
                --text="The archive passed verification." \
                --column="" --column="Action" \
                TRUE "Extract files" \
                FALSE "Combine volumes into one ZIP" \
                FALSE "Test only" 2>/dev/null) || return 1
            case "$selection" in
                "Extract files") ACTION=1 ;;
                "Combine volumes into one ZIP") ACTION=2 ;;
                "Test only") ACTION=3 ;;
                *) return 1 ;;
            esac
            ;;
        kdialog)
            selection=$(kdialog --menu "The archive passed verification. Choose an action:" \
                extract "Extract files" \
                combine "Combine volumes into one ZIP" \
                test "Test only" \
                --title "Choose an action" 2>/dev/null) || return 1
            case "$selection" in
                extract) ACTION=1 ;;
                combine) ACTION=2 ;;
                test) ACTION=3 ;;
                *) return 1 ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac
}

choose_action_terminal() {
    local action

    printf '\nChoose an action:\n'
    printf '  1. Extract files (recommended)\n'
    printf '  2. Combine volumes into one ZIP\n'
    printf '  3. Test only\n'
    IFS= read -r -p "Selection [1]: " action || return 1
    [[ -z "$action" ]] && action=1

    if [[ ! "$action" =~ ^[123]$ ]]; then
        log_error "Invalid action: $action"
        return 1
    fi

    ACTION="$action"
}

choose_action() {
    if [[ -n "$GUI_TOOL" ]]; then
        log_info "Opening action dialog with $GUI_TOOL..."
        if ! choose_action_gui; then
            log_warning "GUI selection was cancelled or failed; switching to terminal mode."
            choose_action_terminal || return 1
        fi
    else
        choose_action_terminal || return 1
    fi

    case "$ACTION" in
        1) extract_archive ;;
        2) combine_archive ;;
        3) log_info "Test complete; no files were changed." ;;
    esac
}

main() {
    print_header "Split ZIP Archive Tool (Linux)"
    find_7z || exit 1
    detect_gui_tool

    if (( $# > 0 )); then
        normalize_user_path "$1"
        if [[ -d "$NORMALIZED_PATH" ]]; then
            INPUT_DIR="$NORMALIZED_PATH"
            find_first_parts || exit 1
            choose_archive || exit 1
        else
            FIRST_PART="$NORMALIZED_PATH"
            validate_first_part || exit 1
        fi
    elif [[ -n "$GUI_TOOL" ]]; then
        log_info "Opening split ZIP file selection dialog with $GUI_TOOL..."
        if ! select_first_part_gui; then
            log_warning "GUI selection was cancelled or failed; switching to terminal mode."
            select_first_part_terminal || exit 1
        fi
        validate_first_part || exit 1
    else
        select_first_part_terminal || exit 1
        validate_first_part || exit 1
    fi

    collect_volume_parts || exit 1

    printf '\n'
    show_volume_summary
    test_archive || exit 1
    choose_action || exit 1

    printf '\n'
    log_info "Done."
}

main "$@"
