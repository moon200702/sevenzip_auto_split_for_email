#requires -Version 5.0

<#
.SYNOPSIS
Creates email-sized split ZIP volumes with 7-Zip.

.DESCRIPTION
Uses a Windows file picker and folder picker when available, with terminal
prompts as a fallback. 7-Zip creates native .zip.001, .zip.002, ... volumes.
#>

[CmdletBinding()]
param(
    [Alias("FilePath")]
    [string[]]$Files = @(),

    [string]$OutputPath = "",

    [ValidateRange(1, 1024)]
    [int]$ChunkSizeMB = 15,

    [switch]$Terminal
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Show-Header {
    param([string]$Text)

    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host ""
}

function Show-Message {
    param(
        [ValidateSet("Info", "Success", "Error", "Warning")]
        [string]$Type,
        [string]$Message
    )

    switch ($Type) {
        "Info" {
            Write-Host "[INFO]" -ForegroundColor Cyan -NoNewline
            Write-Host " $Message"
        }
        "Success" {
            Write-Host "[OK]" -ForegroundColor Green -NoNewline
            Write-Host " $Message" -ForegroundColor Green
        }
        "Error" {
            Write-Host "[ERROR]" -ForegroundColor Red -NoNewline
            Write-Host " $Message" -ForegroundColor Red
        }
        "Warning" {
            Write-Host "[WARN]" -ForegroundColor Yellow -NoNewline
            Write-Host " $Message" -ForegroundColor Yellow
        }
    }
}

function Resolve-UserPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$MustExist
    )

    $value = $Path.Trim()
    if ($value.Length -ge 2) {
        $first = $value.Substring(0, 1)
        $last = $value.Substring($value.Length - 1, 1)
        if (($first -eq '"' -and $last -eq '"') -or
            ($first -eq "'" -and $last -eq "'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }

    $expanded = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($value)
    if ($MustExist) {
        return (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).ProviderPath
    }

    return [System.IO.Path]::GetFullPath($expanded)
}

function Get-SevenZipExecutable {
    $candidates = New-Object System.Collections.Generic.List[string]
    $programFiles = [Environment]::GetEnvironmentVariable("ProgramFiles")
    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")

    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $candidates.Add((Join-Path $programFiles "7-Zip\7z.exe"))
    }
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $candidates.Add((Join-Path $programFilesX86 "7-Zip\7z.exe"))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    foreach ($commandName in @("7z.exe", "7zz.exe", "7za.exe", "7z", "7zz", "7za")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
                return $command.Source
            }
            return $command.Path
        }
    }

    return $null
}

function Initialize-WindowsForms {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return $true
    }
    catch {
        Show-Message -Type "Warning" -Message "Windows Forms is unavailable: $($_.Exception.Message)"
        return $false
    }
}

function Select-FilesWithGui {
    if (-not (Initialize-WindowsForms)) {
        return @()
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
        $dialog.Filter = "All files (*.*)|*.*"
        $dialog.Multiselect = $true
        $dialog.Title = "Select files to ZIP and split"

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return @($dialog.FileNames)
        }
        return @()
    }
    finally {
        $dialog.Dispose()
    }
}

function Select-FilesWithTerminal {
    $selected = New-Object System.Collections.Generic.List[string]
    $counter = 1

    Show-Message -Type "Info" -Message "Enter file paths one per line. Submit an empty line when finished."
    while ($true) {
        $inputPath = Read-Host "File $counter"
        if ([string]::IsNullOrWhiteSpace($inputPath)) {
            if ($selected.Count -gt 0) {
                break
            }
            Show-Message -Type "Error" -Message "Please enter at least one file path."
            continue
        }

        try {
            $resolved = Resolve-UserPath -Path $inputPath -MustExist
            if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                Show-Message -Type "Error" -Message "Not a file: $resolved"
                continue
            }
            $selected.Add($resolved)
            $counter++
        }
        catch {
            Show-Message -Type "Error" -Message "File not found: $inputPath"
        }
    }

    return @($selected)
}

function Select-OutputDirectoryWithGui {
    if (-not (Initialize-WindowsForms)) {
        return $null
    }

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = "Select output folder for split ZIP volumes"
        $dialog.RootFolder = [System.Environment+SpecialFolder]::Desktop
        $dialog.ShowNewFolderButton = $true

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
        return $null
    }
    finally {
        $dialog.Dispose()
    }
}

function Select-OutputDirectoryWithTerminal {
    Show-Message -Type "Info" -Message "Enter output directory (default: current directory):"
    $inputPath = Read-Host ">"
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        return (Get-Location).Path
    }
    return Resolve-UserPath -Path $inputPath
}

function Confirm-InputFiles {
    param([string[]]$InputFiles)

    $confirmed = New-Object System.Collections.Generic.List[string]
    foreach ($inputFile in $InputFiles) {
        try {
            $resolved = Resolve-UserPath -Path $inputFile -MustExist
            if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                throw "Not a file"
            }
            $confirmed.Add($resolved)
        }
        catch {
            throw "Input file not found: $inputFile"
        }
    }
    return @($confirmed)
}

function Prepare-OutputDirectory {
    param([string]$Directory)

    if (Test-Path -LiteralPath $Directory) {
        if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
            throw "Output path is not a directory: $Directory"
        }
    }
    else {
        Show-Message -Type "Info" -Message "Creating output directory: $Directory"
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $probe = Join-Path $Directory ([System.IO.Path]::GetRandomFileName())
    try {
        [System.IO.File]::WriteAllBytes($probe, [byte[]]@())
    }
    finally {
        if (Test-Path -LiteralPath $probe) {
            Remove-Item -LiteralPath $probe -Force
        }
    }
}

function New-ArchivePath {
    param([string]$Directory)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $stem = "archive_$timestamp"
    $suffix = 1
    $candidate = Join-Path $Directory "$stem.zip"

    while ((Test-Path -LiteralPath $candidate) -or
        (Test-Path -LiteralPath "$candidate.001")) {
        $candidate = Join-Path $Directory ("{0}_{1}.zip" -f $stem, $suffix)
        $suffix++
    }

    return $candidate
}

function Get-ArchiveVolumes {
    param([string]$ArchivePath)

    $directory = Split-Path -Parent $ArchivePath
    $archiveName = Split-Path -Leaf $ArchivePath
    $pattern = "^{0}\.(\d{{3,}})$" -f [regex]::Escape($archiveName)

    return @(Get-ChildItem -LiteralPath $directory -File -ErrorAction Stop |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object { [int]$_.Extension.TrimStart('.') })
}

function New-SplitArchive {
    param(
        [string]$SevenZip,
        [string[]]$InputFiles,
        [string]$Directory,
        [int]$VolumeSizeMB
    )

    $archivePath = New-ArchivePath -Directory $Directory
    $arguments = @(
        "a",
        "-tzip",
        "-v${VolumeSizeMB}m",
        $archivePath,
        "--"
    ) + $InputFiles

    Show-Message -Type "Info" -Message "Creating ZIP archive with automatic splitting..."
    Show-Message -Type "Info" -Message "Archive name: $(Split-Path -Leaf $archivePath)"
    Show-Message -Type "Info" -Message "Volume size: $VolumeSizeMB MiB"
    Write-Host ""

    # Keep 7-Zip's progress visible without adding it to this function's return value.
    & $SevenZip @arguments | Out-Host
    $sevenZipExitCode = $LASTEXITCODE
    if ($sevenZipExitCode -ne 0) {
        throw "7-Zip failed with exit code $sevenZipExitCode."
    }

    $volumes = @(Get-ArchiveVolumes -ArchivePath $archivePath)
    if ($volumes.Count -eq 0) {
        throw "7-Zip finished, but no .zip.001 volume was found."
    }

    return [PSCustomObject]@{
        ArchivePath = $archivePath
        Volumes = $volumes
    }
}

function Show-Summary {
    param(
        [string]$Directory,
        [System.IO.FileInfo[]]$Volumes
    )

    Show-Header -Text "OPERATION COMPLETE"
    Show-Message -Type "Info" -Message "Output directory: $Directory"
    Show-Message -Type "Info" -Message "Total volumes: $($Volumes.Count)"
    Write-Host ""

    foreach ($volume in $Volumes) {
        $sizeMiB = "{0:N2}" -f ($volume.Length / 1MB)
        Show-Message -Type "Success" -Message "$($volume.Name) ($sizeMiB MiB)"
    }

    Write-Host ""
    Write-Host "To extract on another computer:" -ForegroundColor Yellow
    Write-Host "  1. Keep every .zip.### file in the same directory."
    Write-Host "  2. Open $($Volumes[0].Name) with 7-Zip."
    Write-Host "  3. Or run .\merge-zip-files.ps1"
    Write-Host ""
}

function Main {
    Show-Header -Text "7-Zip Auto Split for Email (PowerShell/Windows)"

    $sevenZip = Get-SevenZipExecutable
    if ([string]::IsNullOrWhiteSpace($sevenZip)) {
        throw "7-Zip is not installed. Install it from https://www.7-zip.org/ or run: winget install 7zip.7zip"
    }

    $selectedFiles = @()
    if ($Files.Count -gt 0) {
        $selectedFiles = @(Confirm-InputFiles -InputFiles $Files)
    }
    elseif (-not $Terminal) {
        Show-Message -Type "Info" -Message "Opening file selection dialog..."
        $selectedFiles = @(Select-FilesWithGui)
    }

    if ($selectedFiles.Count -eq 0) {
        if (-not $Terminal) {
            Show-Message -Type "Warning" -Message "GUI selection was cancelled or failed; switching to terminal mode."
        }
        $selectedFiles = @(Select-FilesWithTerminal)
    }

    if ($selectedFiles.Count -eq 0) {
        throw "No files were selected."
    }

    Write-Host ""
    Show-Message -Type "Success" -Message "Selected files:"
    foreach ($selectedFile in $selectedFiles) {
        Write-Host "  - $selectedFile"
    }
    Write-Host ""

    $resolvedOutput = $null
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $resolvedOutput = Resolve-UserPath -Path $OutputPath
    }
    elseif (-not $Terminal) {
        Show-Message -Type "Info" -Message "Opening output directory dialog..."
        $resolvedOutput = Select-OutputDirectoryWithGui
    }

    if ([string]::IsNullOrWhiteSpace($resolvedOutput)) {
        if (-not $Terminal) {
            Show-Message -Type "Warning" -Message "GUI selection was cancelled or failed; switching to terminal mode."
        }
        $resolvedOutput = Select-OutputDirectoryWithTerminal
    }

    $resolvedOutput = Resolve-UserPath -Path $resolvedOutput
    Prepare-OutputDirectory -Directory $resolvedOutput
    Write-Host ""

    $result = New-SplitArchive -SevenZip $sevenZip -InputFiles $selectedFiles `
        -Directory $resolvedOutput -VolumeSizeMB $ChunkSizeMB
    Show-Summary -Directory $resolvedOutput -Volumes $result.Volumes
}

try {
    Main
}
catch {
    Show-Message -Type "Error" -Message $_.Exception.Message
    exit 1
}
