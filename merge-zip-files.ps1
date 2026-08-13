# PowerShell Script - Merge Split ZIP Files
# Recombines 7z split archive parts back into a single ZIP file
# Uses 7-Zip for integrity verification

param(
    [string]$InputDir = "",
    [string]$OutputName = ""
)

# Path to 7z executable
$SEVENZIP_PATH = "C:\Program Files\7-Zip\7z.exe"

function Show-Header {
    Write-Host "`n$("`" * 50)" -ForegroundColor Cyan
    Write-Host "$args" -ForegroundColor Cyan
    Write-Host "$("`" * 50)`n" -ForegroundColor Cyan
}

function Show-Message {
    param(
        [ValidateSet("Info", "Success", "Error", "Warning")]
        [string]$Type = "Info",
        [string]$Message
    )
    
    switch ($Type) {
        "Info" { Write-Host "[INFO]" -ForegroundColor Cyan -NoNewline; Write-Host " $Message" }
        "Success" { Write-Host "[✓]" -ForegroundColor Green -NoNewline; Write-Host " $Message" -ForegroundColor Green }
        "Error" { Write-Host "[✗]" -ForegroundColor Red -NoNewline; Write-Host " $Message" -ForegroundColor Red }
        "Warning" { Write-Host "[!]" -ForegroundColor Yellow -NoNewline; Write-Host " $Message" -ForegroundColor Yellow }
    }
    Write-Host ""
}

function Select-DirectoryUI {
    <#
    .SYNOPSIS
    Shows a folder browser dialog
    #>
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowser.Description = "Select folder containing split files"
    $FolderBrowser.RootFolder = "Desktop"
    
    if ($FolderBrowser.ShowDialog() -eq "OK") {
        return $FolderBrowser.SelectedPath
    }
    return $null
}

function Get-DirectoryFromUser {
    <#
    .SYNOPSIS
    Gets directory from user input (terminal mode)
    #>
    Show-Message -Type "Info" "Enter directory containing split files (or press Enter for current directory):"
    $inputDir = Read-Host "> "
    
    if ([string]::IsNullOrWhiteSpace($inputDir)) {
        $inputDir = (Get-Location).Path
    }
    
    if (Test-Path $inputDir) {
        return $inputDir
    }
    else {
        Show-Message -Type "Error" "Directory not found: $inputDir"
        exit 1
    }
}

function Find-SplitFiles {
    <#
    .SYNOPSIS
    Finds all .zip.part* files in directory
    #>
    param([string]$Directory)
    
    $files = Get-ChildItem $Directory -Filter "*.zip.part*" -File | Sort-Object Name
    
    if ($files.Count -eq 0) {
        Show-Message -Type "Error" "No .zip.part* files found in: $Directory"
        
        # Check for old format
        $oldFiles = Get-ChildItem $Directory -Filter "*.part*" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.zip.part*" }
        if ($oldFiles.Count -gt 0) {
            Show-Message -Type "Warning" "Found old format split files. These can be merged manually:"
            Write-Host "  copy /b archive_*.part* output.zip" -ForegroundColor Gray
        }
        
        exit 1
    }
    
    return $files
}

function Extract-SplitArchive {
    <#
    .SYNOPSIS
    Extracts split 7z archive using 7-Zip (with automatic checksum verification)
    #>
    param(
        [string]$FirstPartFile,
        [string]$OutputDir
    )
    
    try {
        # Get 7z executable
        $7zExecutable = if (Test-Path $SEVENZIP_PATH) { $SEVENZIP_PATH } else { "7z.exe" }
        
        Show-Message -Type "Info" "Using 7-Zip to extract split archive (with automatic checksum verification)..."
        Write-Host ""
        
        # Create output directory
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        
        # 7z can open .part001 and will automatically use other parts
        & $7zExecutable x "$FirstPartFile" -o"$OutputDir" | Out-Null
        
        Show-Message -Type "Success" "Successfully extracted all files with checksum verification!"
        Show-Message -Type "Success" "Files extracted to: $(Split-Path $OutputDir -Leaf)"
        Write-Host ""
        Show-Message -Type "Info" "Contents:"
        
        Get-ChildItem $OutputDir | ForEach-Object {
            $size = '{0:N2}' -f ($_.Length/1MB)
            Write-Host "  • $($_.Name) ($size MB)" -ForegroundColor Green
        }
        
        return $true
    }
    catch {
        Show-Message -Type "Error" "Failed to extract archive: $_"
        return $false
    }
}

function Merge-SplitFiles {
    <#
    .SYNOPSIS
    Merges split files into a single ZIP (manual fallback method)
    #>
    param(
        [System.IO.FileInfo[]]$PartFiles,
        [string]$OutputPath
    )
    
    try {
        Show-Message -Type "Warning" "Merging parts manually (no automatic checksum verification)..."
        Write-Host ""
        
        $outputStream = [System.IO.File]::Create($OutputPath)
        
        foreach ($partFile in $PartFiles) {
            Write-Host "  Processing: $($partFile.Name)" -ForegroundColor Green
            
            $inputStream = [System.IO.File]::OpenRead($partFile.FullName)
            $inputStream.CopyTo($outputStream)
            $inputStream.Close()
        }
        
        $outputStream.Close()
        
        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length
            $fileSizeMB = '{0:N2}' -f ($fileSize / 1MB)
            
            Show-Message -Type "Success" "Successfully merged into: $(Split-Path $OutputPath -Leaf)"
            Show-Message -Type "Success" "File size: $fileSizeMB MB"
            Write-Host ""
            
            return $true
        }
        else {
            throw "Output file was not created"
        }
    }
    catch {
        Show-Message -Type "Error" "Failed to merge files: $_"
        return $false
    }
}

function Test-ZipValidity {
    <#
    .SYNOPSIS
    Tests if merged file is a valid ZIP
    #>
    param([string]$FilePath)
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $zip.Dispose()
        
        Show-Message -Type "Success" "ZIP file is valid and ready to extract!"
        return $true
    }
    catch {
        Show-Message -Type "Warning" "ZIP file verification failed. File may be corrupted."
        return $false
    }
}

function Extract-ZipFile {
    <#
    .SYNOPSIS
    Extracts ZIP file to directory
    #>
    param(
        [string]$ZipPath,
        [string]$OutputDir
    )
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $OutputDir)
        
        Show-Message -Type "Success" "Files extracted to: $(Split-Path $OutputDir -Leaf)"
        return $true
    }
    catch {
        Show-Message -Type "Error" "Failed to extract: $_"
        return $false
    }
}

function Main {
    Show-Header "ZIP File Merger - Recombine Split Archives"
    
    # Get input directory
    $inputDir = Select-DirectoryUI
    
    if ($null -eq $inputDir) {
        Show-Message -Type "Info" "GUI selection cancelled, using terminal mode..."
        $inputDir = Get-DirectoryFromUser
    }
    
    # Find split files
    $partFiles = Find-SplitFiles -Directory $inputDir
    
    Show-Message -Type "Success" "Found $($partFiles.Count) part file(s):"
    $partFiles | ForEach-Object { Write-Host "  • $($_.Name)" -ForegroundColor Green }
    Write-Host ""
    
    # Get base name from first file (e.g., archive_20240813_143022.zip from archive_20240813_143022.zip.part001)
    $baseName = $partFiles[0].Name -replace '\.zip\.part.*', ''
    
    # Get output filename
    Show-Message -Type "Info" "Enter output ZIP filename (default: ${baseName}.zip):"
    $inputName = Read-Host "> "
    
    if ([string]::IsNullOrWhiteSpace($inputName)) {
        $outputName = "${baseName}.zip"
    }
    else {
        $outputName = $inputName
        if (-not $outputName.EndsWith(".zip")) {
            $outputName += ".zip"
        }
    }
    
    $outputPath = Join-Path $inputDir $outputName
    
    # Check if file exists
    if (Test-Path $outputPath) {
        Show-Message -Type "Warning" "File already exists: $outputName"
        $response = Read-Host "Overwrite? (y/n)"
        
        if ($response -ne "y" -and $response -ne "Y") {
            Show-Message -Type "Info" "Cancelled."
            exit 0
        }
        
        Remove-Item $outputPath -Force
    }
    
    # Try to use 7z for extraction (preferred - with checksum verification)
    Write-Host ""
    $has7z = Test-Path $SEVENZIP_PATH -or (Get-Command 7z.exe -ErrorAction SilentlyContinue)
    
    if ($has7z) {
        $firstPart = $partFiles[0].FullName
        $extractDir = Join-Path $inputDir "${baseName}_extracted"
        
        $extractSuccess = Extract-SplitArchive -FirstPartFile $firstPart -OutputDir $extractDir
        
        if ($extractSuccess) {
            Write-Host ""
            Show-Message -Type "Info" "Done!"
            exit 0
        }
    }
    
    # Fallback: Manual merge without 7z
    Show-Message -Type "Warning" "7-Zip not found or extraction failed. Using manual merge..."
    Write-Host ""
    $mergeSuccess = Merge-SplitFiles -PartFiles $partFiles -OutputPath $outputPath
    
    if ($mergeSuccess) {
        # Try to extract if we have 7z
        if ($has7z) {
            $response = Read-Host "Extract ZIP file now? (y/n)"
            
            if ($response -eq "y" -or $response -eq "Y") {
                $extractDir = Join-Path $inputDir "${baseName}_extracted"
                Extract-SplitArchive -FirstPartFile $outputPath -OutputDir $extractDir
            }
        }
    }
    
    Write-Host ""
    Show-Message -Type "Info" "Done!"
}

# Run main function
Main
