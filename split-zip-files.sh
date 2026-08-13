#!/bin/bash

################################################################################
# Bash Script - Zip and Split Files for Email
# Uses 7-Zip (p7zip) for compression with built-in splitting and checksum verification
# Requires: 7z (7-zip/p7zip)
################################################################################

set -euo pipefail

# Configuration
CHUNK_SIZE_MB=15
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[✓]${COLOR_RESET} $*"
}

log_error() {
    echo -e "${COLOR_RED}[✗]${COLOR_RESET} $*" >&2
}

log_warning() {
    echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $*"
}

log_bold() {
    echo -e "${COLOR_BOLD}$*${COLOR_RESET}"
}

print_header() {
    echo -e "\n${COLOR_CYAN}$(printf '=%.0s' {1..50})${COLOR_RESET}"
    echo -e "${COLOR_CYAN}$*${COLOR_RESET}"
    echo -e "${COLOR_CYAN}$(printf '=%.0s' {1..50})${COLOR_RESET}\n"
}

################################################################################
# Check for Required Tools
################################################################################

check_7z_installed() {
    if ! command -v 7z &> /dev/null; then
        log_error "7-Zip (p7zip) is not installed!"
        echo ""
        log_warning "Installation instructions:"
        echo "  Ubuntu/Debian: sudo apt-get install p7zip-full"
        echo "  Fedora/RHEL: sudo dnf install p7zip-full"
        echo "  macOS: brew install p7zip"
        echo "  Arch: sudo pacman -S p7zip"
        exit 1
    fi
}

detect_gui_tool() {
    if command -v zenity &> /dev/null; then
        echo "zenity"
    elif command -v kdialog &> /dev/null; then
        echo "kdialog"
    else
        echo ""
    fi
}

################################################################################
# File Selection
################################################################################

select_files_gui() {
    local gui_tool="$1"
    
    case "$gui_tool" in
        zenity)
            zenity --file-selection --multiple --title="Select files to zip and split" 2>/dev/null || return 1
            ;;
        kdialog)
            kdialog --getopenfilename "$HOME" --multiple --title="Select files to zip and split" 2>/dev/null || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

select_directory_gui() {
    local gui_tool="$1"
    local title="$2"
    
    case "$gui_tool" in
        zenity)
            zenity --file-selection --directory --title="$title" 2>/dev/null || return 1
            ;;
        kdialog)
            kdialog --getexistingdirectory "$HOME" --title "$title" 2>/dev/null || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

select_files_terminal() {
    local files=()
    local counter=1
    
    log_info "Enter file paths (one per line, press Enter twice when done):"
    echo ""
    
    while true; do
        read -p "File $counter: " file_path
        
        if [ -z "$file_path" ]; then
            if [ ${#files[@]} -gt 0 ]; then
                break
            fi
            log_error "Please enter at least one file path"
            continue
        fi
        
        if [ -f "$file_path" ]; then
            files+=("$file_path")
            ((counter++))
        else
            log_error "File not found: $file_path"
        fi
    done
    
    printf '%s\n' "${files[@]}"
}

select_directory_terminal() {
    local dir_path
    
    log_info "Enter output directory path (default: current directory):"
    read -p "> " dir_path
    
    if [ -z "$dir_path" ]; then
        dir_path="."
    fi
    
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path" || {
            log_error "Failed to create directory: $dir_path"
            exit 1
        }
    fi
    
    echo "$dir_path"
}

################################################################################
# Archive Creation and Splitting
################################################################################

create_and_split_archive() {
    local output_dir="$1"
    shift
    local files=("$@")
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_name="archive_$timestamp"
    local archive_path="$output_dir/$archive_name.zip"
    
    log_info "Creating 7z archive with automatic splitting..."
    log_info "Archive name: $archive_name.zip"
    log_info "Chunk size: ${CHUNK_SIZE_MB} MB"
    echo ""
    
    # Use 7z with -v parameter to split volumes
    # Format: 7z a -v{size}m archive.zip files...
    if ! 7z a -v${CHUNK_SIZE_MB}m "$archive_path" "${files[@]}" > /dev/null 2>&1; then
        log_error "Failed to create and split archive"
        return 1
    fi
    
    # Check if split files were created
    local split_files=($(find "$output_dir" -maxdepth 1 -type f -name "$archive_name.zip.part*" | sort))
    
    if [ ${#split_files[@]} -eq 0 ]; then
        log_error "No split files were created"
        return 1
    fi
    
    log_success "Archive created and split successfully!"
    log_info "Split files:"
    
    for part_file in "${split_files[@]}"; do
        local size=$(du -h "$part_file" | cut -f1)
        log_success "$(basename "$part_file") ($size)"
    done
    
    log_info "Total chunks: ${#split_files[@]}"
    return 0
}

################################################################################
# Summary
################################################################################

show_summary() {
    local output_dir="$1"
    local total_chunks="$2"
    
    print_header "OPERATION COMPLETE!"
    
    log_info "Output directory: $output_dir"
    log_info "Total chunks: $total_chunks"
    echo -e "\n${COLOR_BOLD}Chunk files created:${COLOR_RESET}"
    
    ls -lh "$output_dir"/*.zip.part* 2>/dev/null | awk '{print "  • " $9 " (" $5 ")"}' || true
    
    echo ""
    log_warning "To extract on another computer:"
    echo "  1. Download all .zip.part* files"
    echo "  2. Open the .zip.part001 file with 7-Zip"
    echo "  3. 7-Zip will automatically:"
    echo "     • Merge all parts"
    echo "     • Verify checksums"
    echo "     • Extract the files"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    print_header "7-Zip Auto Split for Email (Bash/Linux)"
    
    # Check if 7z is installed
    check_7z_installed
    
    local gui_tool=$(detect_gui_tool)
    local selected_files=()
    local output_dir
    
    # Select files
    if [ -n "$gui_tool" ]; then
        log_info "Attempting to open file selection dialog using $gui_tool..."
        if selected_files_output=$(select_files_gui "$gui_tool"); then
            readarray -t selected_files < <(echo "$selected_files_output")
        fi
    fi
    
    if [ ${#selected_files[@]} -eq 0 ]; then
        if [ -n "$gui_tool" ]; then
            log_warning "GUI file selection failed, using terminal mode..."
        fi
        readarray -t selected_files < <(select_files_terminal)
    fi
    
    if [ ${#selected_files[@]} -eq 0 ]; then
        log_error "No files selected. Exiting."
        exit 1
    fi
    
    log_success "Selected files:"
    printf '%s\n' "${selected_files[@]}" | sed 's/^/  • /'
    echo ""
    
    # Select output directory
    log_info "Select output directory..."
    if [ -n "$gui_tool" ]; then
        if output_dir=$(select_directory_gui "$gui_tool" "Select output directory for split archive"); then
            :
        else
            log_warning "GUI directory selection failed, using terminal mode..."
            output_dir=$(select_directory_terminal)
        fi
    else
        output_dir=$(select_directory_terminal)
    fi
    
    # Create and split archive
    echo ""
    if create_and_split_archive "$output_dir" "${selected_files[@]}"; then
        local total_chunks=$(ls -1 "$output_dir"/*.zip.part* 2>/dev/null | wc -l)
        show_summary "$output_dir" "$total_chunks"
    else
        log_error "Failed to create and split archive."
        exit 1
    fi
}

# Run main function
main "$@"
