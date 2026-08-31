# Quick Start Guide

## Windows (PowerShell)

### Prerequisites
Install 7-Zip first: https://www.7-zip.org/

### 1. Split Files (Create ZIP and Split)

```powershell
# Open PowerShell and navigate to the script directory
cd C:\Path\To\sevenzip_auto_split_for_email

# Run the split script
.\split-zip-files.ps1

# Optional: run entirely from the command line
.\split-zip-files.ps1 `
  -Files "C:\Documents\report.pdf","C:\Documents\notes.txt" `
  -OutputPath "C:\email-parts" `
  -ChunkSizeMB 15
```

**What happens:**
1. File selection dialog opens → Select your files
2. Folder selection dialog opens → Choose where to save
3. Files are compressed and automatically split into 15 MiB volumes with 7-Zip
4. Done! Archive files appear in your output folder

**Output example:**
```
archive_20240813_143022.zip.001 (15.0 MiB)
archive_20240813_143022.zip.002 (15.0 MiB)
archive_20240813_143022.zip.003 (8.5 MiB)
```

---

### 2. Extract Files (Recombine Split Files)

**Option A: Using the script**
```powershell
.\merge-zip-files.ps1

# Or select an archive directly and use terminal prompts
.\merge-zip-files.ps1 `
  -InputPath "C:\email-parts\archive_20240813_143022.zip.001" `
  -Terminal
```

The script verifies the archive first, then lets you extract it, combine its
volumes into a single ZIP, or stop after the integrity test.

**Option B: Using 7-Zip GUI**
1. Right-click the `archive_*.zip.001` file
2. Select `7-Zip` → `Extract...`
3. 7-Zip automatically merges all parts and verifies checksums

**Option C: Manual extraction**
```powershell
# Extract from first part (7z will automatically use other parts)
7z x archive_20240813_143022.zip.001
```

---

## Linux / macOS (Bash)

### Prerequisites
```bash
# Install 7-Zip
# Ubuntu/Debian
sudo apt install 7zip zenity

# macOS
brew install p7zip zenity
```

### 1. Split Files (Create ZIP and Split)

```bash
# Navigate to script directory
cd ~/path/to/sevenzip_auto_split_for_email

# Run the split script
./split-zip-files.sh
```

**What happens:**
1. File selection dialog opens (if Zenity installed) → Select your files
2. Folder selection dialog opens → Choose where to save
3. Files are compressed and automatically split into 15 MiB volumes with 7-Zip
4. Done! Archive files appear in your output folder

**If GUI doesn't appear:**
- Enter file paths manually
- Script will ask for directory

---

### 2. Extract Files (Recombine Split Files)

**Option A: Using the script**
```bash
./merge-zip-files.sh
```

The script verifies the complete archive first, then offers three actions:
extract the files, combine the volumes into one ZIP, or test only. It uses a
file picker for the first `.zip.001` volume and a folder picker for the output,
with terminal prompts as a fallback.

You can also provide the first volume directly:

```bash
./merge-zip-files.sh /path/to/archive.zip.001
```

**Option B: Using 7-Zip directly**
```bash
# Extract from first part (7z will automatically use other parts)
7z x archive_20240813_143022.zip.001
```

**Option C: Manual merge** (without automatic checksum verification)
```bash
# Navigate to folder with split files
cd /path/to/split/files

# Merge all parts
cat archive.zip.[0-9][0-9][0-9] > output.zip

# Extract
unzip output.zip
```

---

## Installation Requirements

### Windows
- 7-Zip: https://www.7-zip.org/
- PowerShell 5.0+ (included in Windows 10+)

Install command:
```powershell
# Using Chocolatey
choco install 7zip

# Using Windows Package Manager
winget install 7zip
```

### Linux
```bash
# Debian/Ubuntu
sudo apt install 7zip zenity

# Fedora/RHEL
sudo dnf install p7zip-full zenity

# Arch Linux
sudo pacman -S p7zip zenity
```

### macOS
```bash
brew install p7zip zenity
```

---

## Common Tasks

### Send Files via Email

1. **Split the files:**
   ```bash
   ./split-zip-files.sh
   ```

2. **Attach each part separately:**
   - Part 001 → Email 1
   - Part 002 → Email 2
   - etc.

3. **Recipient extracts with 7-Zip:**
   - Download all `.zip.###` files
   - Right-click `archive_*.zip.001`
   - Select `7-Zip` → `Extract`
   - 7-Zip automatically:
     - Merges all parts
     - Verifies checksums
     - Extracts files

### Change Chunk Size

The Bash script can be configured in the file; PowerShell accepts a parameter
for each run:

**Bash:**
```bash
CHUNK_SIZE_MB=15  # Change to desired size, e.g., 20
```

**PowerShell:**
```powershell
.\split-zip-files.ps1 -ChunkSizeMB 20
```

### Compress Specific Files

When prompted for files, enter:
- Full paths: `/home/user/Documents/file.pdf`
- Relative paths: `~/Documents/file.pdf` (Linux/Mac)

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "7-Zip not installed" | Download from https://www.7-zip.org/ |
| "Command not found" | Make sure script is executable: `chmod +x *.sh` |
| "GUI dialog won't open" | Install zenity: `sudo apt-get install zenity` |
| "Extract fails on parts" | Ensure all `.zip.###` files are together |
| "Part files won't merge" | Use 7-Zip to open `.zip.001` (it handles the rest automatically) |

---

## Tips

✅ **Keep all parts together** - Don't separate part files  
✅ **Use 7-Zip to extract** - Automatic checksum verification  
✅ **Test before sharing** - Verify extracted files work  
✅ **Timestamp helps** - Archive names include creation date  
✅ **Volume size for email** - Adjust 15 MiB if your provider has a lower attachment limit

---

## Key Difference: Checksum Verification

When you extract using 7-Zip (recommended):
- ✅ Automatically verifies file integrity during extraction
- ✅ Merges all parts automatically
- ✅ Detects corrupted parts immediately
- ✅ Safe for email distribution

When you manually merge:
- ⚠️ No automatic integrity checking
- ⚠️ Must merge manually with `cat` command
- ⚠️ No detection of corruption

---

**Ready to use!** Start with `./split-zip-files.sh` or `.\split-zip-files.ps1`
