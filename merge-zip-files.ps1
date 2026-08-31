#requires -Version 5.0

<#
.SYNOPSIS
Validates, extracts, or combines native 7-Zip split ZIP volumes.

.DESCRIPTION
Select the first .zip.001 volume. The script finds its sibling volumes,
checks their numbering, verifies the archive with 7-Zip, and then offers to
extract, combine into one ZIP, or stop after verification.
#>

[CmdletBinding()]
param(
    [Alias("InputDir")]
    [string]$InputPath = "",

    [string]$OutputName = "",

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
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        return $true
    }
    catch {
        Show-Message -Type "Warning" -Message "Windows Forms is unavailable: $($_.Exception.Message)"
        return $false
    }
}

function Select-FirstVolumeWithGui {
    if (-not (Initialize-WindowsForms)) {
        return $null
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
        $dialog.Filter = "First split ZIP volume (*.zip.001)|*.zip.001|All files (*.*)|*.*"
        $dialog.Multiselect = $false
        $dialog.Title = "Select the first split ZIP volume (.zip.001)"

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        return $null
    }
    finally {
        $dialog.Dispose()
    }
}

function Select-FirstVolumeWithTerminal {
    Show-Message -Type "Info" -Message "Enter the path to the first split ZIP volume (.zip.001):"
    $inputValue = Read-Host ">"
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return $null
    }
    return Resolve-UserPath -Path $inputValue -MustExist
}

function Select-FirstVolumeFromDirectory {
    param([string]$Directory)

    $firstVolumes = @(Get-ChildItem -LiteralPath $Directory -Filter "*.zip.001" -File |
        Sort-Object Name)
    if ($firstVolumes.Count -eq 0) {
        throw "No .zip.001 files found in: $Directory"
    }
    if ($firstVolumes.Count -eq 1) {
        return $firstVolumes[0].FullName
    }

    Show-Message -Type "Info" -Message "Multiple split archives were found:"
    for ($index = 0; $index -lt $firstVolumes.Count; $index++) {
        Write-Host ("  {0}. {1}" -f ($index + 1), $firstVolumes[$index].Name)
    }

    while ($true) {
        $selection = Read-Host "Choose an archive [1-$($firstVolumes.Count)]"
        $number = 0
        if ([int]::TryParse($selection, [ref]$number) -and
            $number -ge 1 -and $number -le $firstVolumes.Count) {
            return $firstVolumes[$number - 1].FullName
        }
        Show-Message -Type "Error" -Message "Invalid selection: $selection"
    }
}

function Confirm-FirstVolume {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "No split ZIP volume was selected."
    }

    $resolved = Resolve-UserPath -Path $Path -MustExist
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Not a file: $resolved"
    }
    if (-not $resolved.EndsWith(".zip.001", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Please select the first volume ending in .zip.001."
    }
    return $resolved
}

function Get-ArchiveInformation {
    param([string]$FirstVolume)

    $archivePath = $FirstVolume.Substring(0, $FirstVolume.Length - 4)
    $archiveName = Split-Path -Leaf $archivePath
    $directory = Split-Path -Parent $archivePath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($archiveName)
    $pattern = "^{0}\.(\d{{3,}})$" -f [regex]::Escape($archiveName)

    $volumes = @(Get-ChildItem -LiteralPath $directory -File |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object { [int]$_.Name.Substring($archiveName.Length + 1) })
    if ($volumes.Count -eq 0) {
        throw "No volumes found for: $archiveName"
    }

    $expected = 1
    foreach ($volume in $volumes) {
        $numberText = $volume.Name.Substring($archiveName.Length + 1)
        $number = [int]$numberText
        if ($number -ne $expected) {
            throw ("Missing volume {0:D3} before {1}" -f $expected, $volume.Name)
        }
        $expected++
    }

    return [PSCustomObject]@{
        FirstVolume = $FirstVolume
        ArchivePath = $archivePath
        ArchiveName = $archiveName
        BaseName = $baseName
        InputDirectory = $directory
        Volumes = $volumes
    }
}

function Show-VolumeSummary {
    param([PSCustomObject]$Archive)

    Show-Message -Type "Success" -Message "Selected archive: $($Archive.ArchiveName)"
    Show-Message -Type "Info" -Message "Volumes found: $($Archive.Volumes.Count)"
    foreach ($volume in $Archive.Volumes) {
        Write-Host "  - $($volume.Name)"
    }
    Write-Host ""
}

function Test-SplitArchive {
    param(
        [string]$SevenZip,
        [string]$FirstVolume
    )

    Show-Message -Type "Info" -Message "Testing all volumes with 7-Zip..."
    Write-Host ""
    & $SevenZip "t" $FirstVolume
    $sevenZipExitCode = $LASTEXITCODE
    if ($sevenZipExitCode -ne 0) {
        throw "Archive verification failed with 7-Zip exit code $sevenZipExitCode. A volume may be missing or corrupted."
    }
    Write-Host ""
    Show-Message -Type "Success" -Message "Archive verification passed."
}

function Select-ActionWithGui {
    if (-not (Initialize-WindowsForms)) {
        return $null
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Choose an action"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(460, 150)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "The archive passed verification. What would you like to do?"
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $form.Controls.Add($label)

    $extractButton = New-Object System.Windows.Forms.Button
    $extractButton.Text = "Extract files"
    $extractButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $extractButton.Size = New-Object System.Drawing.Size(125, 35)
    $extractButton.Location = New-Object System.Drawing.Point(20, 75)
    $form.Controls.Add($extractButton)

    $combineButton = New-Object System.Windows.Forms.Button
    $combineButton.Text = "Combine ZIP"
    $combineButton.DialogResult = [System.Windows.Forms.DialogResult]::No
    $combineButton.Size = New-Object System.Drawing.Size(125, 35)
    $combineButton.Location = New-Object System.Drawing.Point(165, 75)
    $form.Controls.Add($combineButton)

    $testButton = New-Object System.Windows.Forms.Button
    $testButton.Text = "Test only"
    $testButton.DialogResult = [System.Windows.Forms.DialogResult]::Ignore
    $testButton.Size = New-Object System.Drawing.Size(125, 35)
    $testButton.Location = New-Object System.Drawing.Point(310, 75)
    $form.Controls.Add($testButton)

    $form.AcceptButton = $extractButton
    try {
        $result = $form.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            return "Extract"
        }
        if ($result -eq [System.Windows.Forms.DialogResult]::No) {
            return "Combine"
        }
        if ($result -eq [System.Windows.Forms.DialogResult]::Ignore) {
            return "Test"
        }
        return $null
    }
    finally {
        $form.Dispose()
    }
}

function Select-ActionWithTerminal {
    Write-Host ""
    Write-Host "Choose an action:"
    Write-Host "  1. Extract files (recommended)"
    Write-Host "  2. Combine volumes into one ZIP"
    Write-Host "  3. Test only"
    $selection = Read-Host "Selection [1]"
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return "Extract"
    }

    switch ($selection) {
        "1" { return "Extract" }
        "2" { return "Combine" }
        "3" { return "Test" }
        default { throw "Invalid action: $selection" }
    }
}

function Select-DestinationDirectoryWithGui {
    param([string]$Description)

    if (-not (Initialize-WindowsForms)) {
        return $null
    }

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = $Description
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

function Select-DestinationDirectoryWithTerminal {
    param(
        [string]$Description,
        [string]$DefaultDirectory
    )

    Show-Message -Type "Info" -Message "$Description (default: $DefaultDirectory):"
    $inputValue = Read-Host ">"
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return $DefaultDirectory
    }
    return Resolve-UserPath -Path $inputValue
}

function Select-DestinationDirectory {
    param(
        [string]$Description,
        [string]$DefaultDirectory
    )

    $destination = $null
    if (-not $Terminal) {
        Show-Message -Type "Info" -Message "Opening output directory dialog..."
        $destination = Select-DestinationDirectoryWithGui -Description $Description
    }
    if ([string]::IsNullOrWhiteSpace($destination)) {
        if (-not $Terminal) {
            Show-Message -Type "Warning" -Message "GUI selection was cancelled or failed; switching to terminal mode."
        }
        $destination = Select-DestinationDirectoryWithTerminal `
            -Description $Description -DefaultDirectory $DefaultDirectory
    }

    $destination = Resolve-UserPath -Path $destination
    if (Test-Path -LiteralPath $destination) {
        if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
            throw "Output path is not a directory: $destination"
        }
    }
    else {
        Show-Message -Type "Info" -Message "Creating output directory: $destination"
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
    }
    return $destination
}

function Confirm-YesNo {
    param([string]$Question)

    if (-not $Terminal -and (Initialize-WindowsForms)) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            $Question,
            "Confirmation",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return $result -eq [System.Windows.Forms.DialogResult]::Yes
    }

    $response = Read-Host "$Question (y/N)"
    return $response -match '^[Yy]$'
}

function Test-DirectoryHasContents {
    param([string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $false
    }
    return $null -ne (Get-ChildItem -LiteralPath $Directory -Force | Select-Object -First 1)
}

function Expand-SplitArchive {
    param(
        [string]$SevenZip,
        [PSCustomObject]$Archive
    )

    $destination = Select-DestinationDirectory `
        -Description "Select output directory for extracted files" `
        -DefaultDirectory $Archive.InputDirectory
    $extractDirectory = Join-Path $destination "$($Archive.BaseName)_extracted"

    if (Test-DirectoryHasContents -Directory $extractDirectory) {
        Show-Message -Type "Warning" -Message "Extraction directory is not empty: $extractDirectory"
        if (-not (Confirm-YesNo -Question "Overwrite files with matching names?")) {
            Show-Message -Type "Info" -Message "Extraction cancelled."
            return
        }
    }

    if (-not (Test-Path -LiteralPath $extractDirectory)) {
        New-Item -ItemType Directory -Path $extractDirectory -Force | Out-Null
    }

    Write-Host ""
    Show-Message -Type "Info" -Message "Extracting files..."
    & $SevenZip "x" $Archive.FirstVolume "-o$extractDirectory" "-aoa" "-y"
    $sevenZipExitCode = $LASTEXITCODE
    if ($sevenZipExitCode -ne 0) {
        throw "Extraction failed with 7-Zip exit code $sevenZipExitCode."
    }

    Write-Host ""
    Show-Message -Type "Success" -Message "Files extracted to: $extractDirectory"
}

function Join-SplitArchive {
    param(
        [string]$SevenZip,
        [PSCustomObject]$Archive,
        [string]$RequestedOutputName
    )

    $destination = Select-DestinationDirectory `
        -Description "Select output directory for the combined ZIP" `
        -DefaultDirectory $Archive.InputDirectory

    $combinedName = $Archive.ArchiveName
    if (-not [string]::IsNullOrWhiteSpace($RequestedOutputName)) {
        $combinedName = [System.IO.Path]::GetFileName($RequestedOutputName.Trim())
        if (-not $combinedName.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
            $combinedName = "$combinedName.zip"
        }
    }
    $outputPath = Join-Path $destination $combinedName

    if (Test-Path -LiteralPath $outputPath) {
        Show-Message -Type "Warning" -Message "File already exists: $outputPath"
        if (-not (Confirm-YesNo -Question "Overwrite the existing ZIP?")) {
            Show-Message -Type "Info" -Message "Combine cancelled."
            return
        }
    }

    $tempPath = Join-Path $destination (".combined-{0}.tmp" -f [guid]::NewGuid().ToString("N"))
    $outputStream = $null
    try {
        $outputStream = [System.IO.File]::Open(
            $tempPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )

        foreach ($volume in $Archive.Volumes) {
            Show-Message -Type "Info" -Message "Combining $($volume.Name)..."
            $inputStream = $null
            try {
                $inputStream = [System.IO.File]::OpenRead($volume.FullName)
                $inputStream.CopyTo($outputStream)
            }
            finally {
                if ($null -ne $inputStream) {
                    $inputStream.Dispose()
                }
            }
        }
        $outputStream.Dispose()
        $outputStream = $null

        Show-Message -Type "Info" -Message "Testing the combined ZIP before saving it..."
        & $SevenZip "t" $tempPath | Out-Host
        $sevenZipExitCode = $LASTEXITCODE
        if ($sevenZipExitCode -ne 0) {
            throw "Combined ZIP verification failed with 7-Zip exit code $sevenZipExitCode."
        }

        [System.IO.File]::Copy($tempPath, $outputPath, $true)
        Show-Message -Type "Success" -Message "Combined ZIP saved to: $outputPath"
    }
    finally {
        if ($null -ne $outputStream) {
            $outputStream.Dispose()
        }
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

function Main {
    Show-Header -Text "Split ZIP Archive Tool (PowerShell/Windows)"

    $sevenZip = Get-SevenZipExecutable
    if ([string]::IsNullOrWhiteSpace($sevenZip)) {
        throw "7-Zip is not installed. Install it from https://www.7-zip.org/ or run: winget install 7zip.7zip"
    }

    $firstVolume = $null
    if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        $resolvedInput = Resolve-UserPath -Path $InputPath -MustExist
        if (Test-Path -LiteralPath $resolvedInput -PathType Container) {
            $firstVolume = Select-FirstVolumeFromDirectory -Directory $resolvedInput
        }
        else {
            $firstVolume = $resolvedInput
        }
    }
    elseif (-not $Terminal) {
        Show-Message -Type "Info" -Message "Opening split ZIP file selection dialog..."
        $firstVolume = Select-FirstVolumeWithGui
    }

    if ([string]::IsNullOrWhiteSpace($firstVolume)) {
        if (-not $Terminal) {
            Show-Message -Type "Warning" -Message "GUI selection was cancelled or failed; switching to terminal mode."
        }
        $firstVolume = Select-FirstVolumeWithTerminal
    }

    $firstVolume = Confirm-FirstVolume -Path $firstVolume
    $archive = Get-ArchiveInformation -FirstVolume $firstVolume
    Write-Host ""
    Show-VolumeSummary -Archive $archive
    Test-SplitArchive -SevenZip $sevenZip -FirstVolume $archive.FirstVolume

    $action = $null
    if (-not $Terminal) {
        Show-Message -Type "Info" -Message "Opening action dialog..."
        $action = Select-ActionWithGui
    }
    if ([string]::IsNullOrWhiteSpace($action)) {
        if (-not $Terminal) {
            Show-Message -Type "Warning" -Message "GUI selection was cancelled or failed; switching to terminal mode."
        }
        $action = Select-ActionWithTerminal
    }

    switch ($action) {
        "Extract" { Expand-SplitArchive -SevenZip $sevenZip -Archive $archive }
        "Combine" {
            Join-SplitArchive -SevenZip $sevenZip -Archive $archive `
                -RequestedOutputName $OutputName
        }
        "Test" { Show-Message -Type "Info" -Message "Test complete; no files were changed." }
        default { throw "Unknown action: $action" }
    }

    Write-Host ""
    Show-Message -Type "Info" -Message "Done."
}

try {
    Main
}
catch {
    Show-Message -Type "Error" -Message $_.Exception.Message
    exit 1
}
