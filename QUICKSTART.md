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
```

**What happens:**
1. File selection dialog opens → Select your files
2. Folder selection dialog opens → Choose where to save
3. Files are compressed and automatically split into 15MB chunks with 7-Zip
4. Done! Archive files appear in your output folder

**Output example:**
```
archive_20240813_143022.zip.part001 (15.0 MB)
archive_20240813_143022.zip.part002 (15.0 MB)
archive_20240813_143022.zip.part003 (8.5 MB)
```

---

### 2. Extract Files (Recombine Split Files)

**Option A: Using the script**
```powershell
.\merge-zip-files.ps1
```

**Option B: Using 7-Zip GUI**
1. Right-click `archive_*.zip.part001` file
2. Select `7-Zip` → `Extract...`
3. 7-Zip automatically merges all parts and verifies checksums

**Option C: Manual extraction**
```powershell
# Extract from first part (7z will automatically use other parts)
7z x archive_20240813_143022.zip.part001
```

---

## Linux / macOS (Bash)

### Prerequisites
```bash
# Install 7-Zip
# Ubuntu/Debian
sudo apt-get install p7zip-full zenity

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
3. Files are compressed and automatically split into 15MB chunks with 7-Zip
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

**Option B: Using 7-Zip directly**
```bash
# Extract from first part (7z will automatically use other parts)
7z x archive_20240813_143022.zip.part001
```

**Option C: Manual merge** (without automatic checksum verification)
```bash
# Navigate to folder with split files
cd /path/to/split/files

# Merge all parts
cat archive_*.zip.part* > output.zip

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
sudo apt-get install p7zip-full zenity

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
   - Download all `.zip.part*` files
   - Right-click `archive_*.zip.part001`
   - Select `7-Zip` → `Extract`
   - 7-Zip automatically:
     - Merges all parts
     - Verifies checksums
     - Extracts files

### Change Chunk Size

Edit the script and change this line:

**Bash:**
```bash
CHUNK_SIZE_MB=15  # Change to desired size, e.g., 20
```

**PowerShell:**
```powershell
$CHUNK_SIZE_MB = 15  # Change to desired size, e.g., 20
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
| "Extract fails on parts" | Ensure all `.zip.part*` files are together |
| "Part files won't merge" | Use 7-Zip to open .part001 (it handles rest automatically) |

---

## Tips

✅ **Keep all parts together** - Don't separate part files  
✅ **Use 7-Zip to extract** - Automatic checksum verification  
✅ **Test before sharing** - Verify extracted files work  
✅ **Timestamp helps** - Archive names include creation date  
✅ **Chunk size for email** - 15MB fits most email servers  

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
