#!/bin/bash

################################################################################
# Merge Split ZIP Files (Bash/Linux)
# Recombines 7z split archive parts back into a single ZIP file
# Uses 7-Zip for integrity verification
################################################################################

set -euo pipefail

COLOR_CYAN='\033[0;36m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

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

print_header() {
    echo -e "\n${COLOR_CYAN}$(printf '=%.0s' {1..50})${COLOR_RESET}"
    echo -e "${COLOR_CYAN}$*${COLOR_RESET}"
    echo -e "${COLOR_CYAN}$(printf '=%.0s' {1..50})${COLOR_RESET}\n"
}

main() {
    print_header "ZIP File Merger - Recombine Split Archives"
    
    local input_dir current_dir
    
    # Ask for input directory
    log_info "Enter directory containing split files (or press Enter for current directory):"
    read -p "> " input_dir
    
    if [ -z "$input_dir" ]; then
        input_dir="."
    fi
    
    if [ ! -d "$input_dir" ]; then
        log_error "Directory not found: $input_dir"
        exit 1
    fi
    
    # Find split files (7z format: .zip.part001, .zip.part002, etc)
    local part_files=($(find "$input_dir" -maxdepth 1 -type f -name "*.zip.part*" | sort))
    
    if [ ${#part_files[@]} -eq 0 ]; then
        log_error "No .zip.part* files found in: $input_dir"
        log_warning "Looking for alternative formats..."
        
        # Check for old format .part* files
        local old_format=($(find "$input_dir" -maxdepth 1 -type f -name "*.part*" ! -name "*.zip.part*" | sort))
        if [ ${#old_format[@]} -gt 0 ]; then
            log_warning "Found old format split files. These can be merged manually:"
            echo "  cat archive_*.part* > output.zip"
            echo "  unzip output.zip"
        fi
        exit 1
    fi
    
    log_success "Found ${#part_files[@]} part file(s):"
    printf '%s\n' "${part_files[@]}" | sed 's/^/  • /'
    echo ""
    
    # Get base name from first file (e.g., archive_20240813_143022.zip from archive_20240813_143022.zip.part001)
    local first_file=$(basename "${part_files[0]}")
    local base_name="${first_file%.zip.part*}"
    
    # Get output filename
    log_info "Enter output ZIP filename (default: ${base_name}.zip):"
    read -p "> " output_name
    
    if [ -z "$output_name" ]; then
        output_name="${base_name}.zip"
    fi
    
    # Ensure .zip extension
    if [[ ! "$output_name" == *.zip ]]; then
        output_name="${output_name}.zip"
    fi
    
    local output_path="$input_dir/$output_name"
    
    if [ -f "$output_path" ]; then
        log_warning "File already exists: $output_path"
        read -p "Overwrite? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled."
            exit 0
        fi
        rm "$output_path"
    fi
    
    # Check if 7z is available for extraction
    local has_7z=false
    if command -v 7z &> /dev/null; then
        has_7z=true
    fi
    
    # Use 7z to extract directly from .zip.part001
    # This method automatically merges, verifies checksums, and extracts
    if [ "$has_7z" = true ]; then
        log_info "Using 7z to extract split archive (with automatic checksum verification)..."
        echo ""
        
        # 7z can open .part001 and will automatically use other parts
        local first_part="${part_files[0]}"
        local extract_dir="${input_dir}/${base_name}_extracted"
        
        if 7z x "$first_part" -o"$extract_dir" > /dev/null 2>&1; then
            log_success "Successfully extracted all files with checksum verification!"
            log_success "Files extracted to: $(basename "$extract_dir")"
            echo ""
            log_info "Contents:"
            ls -lh "$extract_dir" | tail -n +2 | awk '{print "  • " $9 " (" $5 ")"}'
        else
            log_error "Failed to extract archive. Files may be corrupted."
            exit 1
        fi
    else
        # Fallback: Manual merge without 7z
        log_warning "7z not found. Merging parts manually (no automatic checksum verification)..."
        echo ""
        
        if cat "${part_files[@]}" > "$output_path"; then
            local file_size=$(du -h "$output_path" | cut -f1)
            log_success "Successfully merged into: $output_name"
            log_success "File size: $file_size"
            echo ""
            
            # Try to extract if unzip is available
            if command -v unzip &> /dev/null; then
                read -p "Extract ZIP file now? (y/n): " -n 1 -r
                echo ""
                
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    local extract_dir="${input_dir}/${base_name}_extracted"
                    mkdir -p "$extract_dir"
                    unzip -q "$output_path" -d "$extract_dir"
                    log_success "Files extracted to: $(basename "$extract_dir")"
                fi
            fi
        else
            log_error "Failed to merge files"
            exit 1
        fi
    fi
    
    echo ""
    log_info "Done!"
}

main "$@"
