# PowerShell Script - Zip and Split Files for Email
# Uses 7-Zip for compression with built-in splitting and checksum verification
# Supports GUI file selection and automatic 15MB chunk splitting

param(
    [string]$FilePath = ""
)

# Set maximum chunk size (15MB)
$CHUNK_SIZE_MB = 15
$SEVENZIP_PATH = "C:\Program Files\7-Zip\7z.exe"

function Check-SevenZipInstalled {
    <#
    .SYNOPSIS
    Checks if 7-Zip is installed on the system
    #>
    if (Test-Path $SEVENZIP_PATH) {
        return $true
    }
    
    # Try to find it in PATH
    try {
        $null = & 7z.exe -? 2>$null
        return $true
    }
    catch {
        return $false
    }
}
    <#
    .SYNOPSIS
    Shows a Windows Forms file selection dialog (GUI)
    #>
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    $OpenFileDialog.Filter = "All Files (*.*)|*.*"
    $OpenFileDialog.Multiselect = $true
    $OpenFileDialog.Title = "Select files to zip and split"
    
    if ($OpenFileDialog.ShowDialog() -eq "OK") {
        return $OpenFileDialog.FileNames
    }
    return $null
}

function Show-FolderDialog {
    <#
    .SYNOPSIS
    Shows a folder selection dialog for output directory
    #>
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowser.Description = "Select output folder for split zip files"
    $FolderBrowser.RootFolder = "Desktop"
    
    if ($FolderBrowser.ShowDialog() -eq "OK") {
        return $FolderBrowser.SelectedPath
    }
    return $null
}

function Select-FilesViaTerminal {
    <#
    .SYNOPSIS
    Terminal-based file selection (fallback if no GUI available)
    #>
    Write-Host "`n=== File Selection ===" -ForegroundColor Cyan
    Write-Host "Enter file paths (one per line, empty line to finish):" -ForegroundColor Yellow
    
    $files = @()
    $counter = 1
    
    while ($true) {
        $input_path = Read-Host "File $counter"
        
        if ([string]::IsNullOrWhiteSpace($input_path)) {
            if ($files.Count -gt 0) {
                break
            }
            Write-Host "Please enter at least one file path." -ForegroundColor Red
            continue
        }
        
        if (Test-Path $input_path) {
            $files += $input_path
            $counter++
        }
        else {
            Write-Host "File not found: $input_path" -ForegroundColor Red
        }
    }
    
    return $files
}

function Create-AndSplitArchive {
    <#
    .SYNOPSIS
    Creates a 7z archive with automatic splitting using 7zip's -v parameter
    #>
    param(
        [string[]]$Files,
        [string]$OutputPath
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $archiveName = "archive_$timestamp"
    $archivePath = Join-Path $OutputPath $archiveName
    
    Write-Host "`nCreating 7z archive with automatic splitting..." -ForegroundColor Cyan
    Write-Host "Archive name: $archiveName" -ForegroundColor Yellow
    Write-Host "Chunk size: $CHUNK_SIZE_MB MB" -ForegroundColor Yellow
    
    try {
        # Use 7zip with -v parameter to split volumes
        # Format: 7z a -v{size}m archive.7z files...
        $volumeSize = "${CHUNK_SIZE_MB}m"
        
        # Resolve 7zip path
        $7zExecutable = if (Test-Path $SEVENZIP_PATH) { $SEVENZIP_PATH } else { "7z.exe" }
        
        # Create archive with splitting
        & $7zExecutable a -tzip -v${volumeSize} "$archivePath.zip" $Files 2>&1 | ForEach-Object {
            if ($_ -match "error|Error|ERROR") {
                Write-Host $_ -ForegroundColor Red
            }
        }
        
        # Check if split files were created
        $splitFiles = Get-ChildItem "$OutputPath" -Filter "$archiveName.zip.part*" -ErrorAction SilentlyContinue
        
        if ($splitFiles.Count -gt 0) {
            Write-Host "`n✓ Archive created and split successfully!" -ForegroundColor Green
            
            # Display split file information
            Write-Host "Split files:" -ForegroundColor Cyan
            $splitFiles | Sort-Object Name | ForEach-Object {
                $fileSize = '{0:N2}' -f ($_.Length/1MB)
                Write-Host "  ✓ $($_.Name) ($fileSize MB)" -ForegroundColor Green
            }
            
            Write-Host "`nTotal chunks: $($splitFiles.Count)" -ForegroundColor Yellow
            return $true
        }
        else {
            throw "No split files were created"
        }
    }
    catch {
        Write-Host "✗ Error creating archive: $_" -ForegroundColor Red
        return $false
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
    Shows a summary of the operation
    #>
    param(
        [string]$OutputPath,
        [int]$TotalChunks
    )
    
    Write-Host "`n" + "="*50 -ForegroundColor Cyan
    Write-Host "OPERATION COMPLETE!" -ForegroundColor Green
    Write-Host "="*50 -ForegroundColor Cyan
    Write-Host "Output directory: $OutputPath" -ForegroundColor Yellow
    Write-Host "Total chunks: $TotalChunks" -ForegroundColor Yellow
    Write-Host "`nChunk files created:" -ForegroundColor Cyan
    
    Get-ChildItem $OutputPath -Filter "*.zip.part*" | Sort-Object Name | ForEach-Object {
        $size = '{0:N2}' -f ($_.Length/1MB)
        Write-Host "  • $($_.Name) ($size MB)" -ForegroundColor Green
    }
    
    Write-Host "`nTo extract on another computer:" -ForegroundColor Yellow
    Write-Host "  1. Download all .zip.part* files" -ForegroundColor Gray
    Write-Host "  2. Open the .zip.part001 file with 7-Zip" -ForegroundColor Gray
    Write-Host "  3. 7-Zip will automatically merge, verify checksums, and extract" -ForegroundColor Gray
    Write-Host "`n"
}

# Main execution
function Main {
    Write-Host "`n" + "="*50 -ForegroundColor Cyan
    Write-Host "7-Zip Auto Split for Email (PowerShell)" -ForegroundColor Cyan
    Write-Host "="*50 -ForegroundColor Cyan
    
    # Check if 7-Zip is installed
    if (-not (Check-SevenZipInstalled)) {
        Write-Host "`n✗ ERROR: 7-Zip is not installed!" -ForegroundColor Red
        Write-Host "`nPlease install 7-Zip from: https://www.7-zip.org/" -ForegroundColor Yellow
        Write-Host "Or install via Chocolatey: choco install 7zip" -ForegroundColor Yellow
        exit 1
    }
    
    # Select files
    Write-Host "`nAttempting to open file selection dialog..." -ForegroundColor Yellow
    $selectedFiles = Show-FileDialog
    
    if ($null -eq $selectedFiles -or $selectedFiles.Count -eq 0) {
        Write-Host "No files selected via GUI, using terminal mode..." -ForegroundColor Yellow
        $selectedFiles = Select-FilesViaTerminal
    }
    
    if ($null -eq $selectedFiles -or $selectedFiles.Count -eq 0) {
        Write-Host "✗ No files selected. Exiting." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`nSelected files:" -ForegroundColor Green
    $selectedFiles | ForEach-Object { Write-Host "  • $_" -ForegroundColor Green }
    
    # Select output directory
    Write-Host "`nSelect output directory..." -ForegroundColor Yellow
    $outputPath = Show-FolderDialog
    
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        Write-Host "No output directory selected. Using Desktop..." -ForegroundColor Yellow
        $outputPath = [Environment]::GetFolderPath("Desktop")
    }
    
    if (-not (Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
    }
    
    # Create and split archive
    $success = Create-AndSplitArchive -Files $selectedFiles -OutputPath $outputPath
    
    if ($success) {
        $splitFiles = Get-ChildItem "$outputPath" -Filter "archive_*.zip.part*" | Measure-Object
        Show-Summary -OutputPath $outputPath -TotalChunks $splitFiles.Count
        
        Write-Host "`nNote: To extract on another computer, use 7-Zip to open the first .zip.part001 file" -ForegroundColor Cyan
        Write-Host "7-Zip will automatically:" -ForegroundColor Cyan
        Write-Host "  • Merge all parts" -ForegroundColor Cyan
        Write-Host "  • Verify checksums" -ForegroundColor Cyan
        Write-Host "  • Extract the files" -ForegroundColor Cyan
    }
    else {
        Write-Host "✗ Failed to create and split archive." -ForegroundColor Red
        exit 1
    }
}

# Run main function
Main
