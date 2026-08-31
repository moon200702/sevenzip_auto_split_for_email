# 7-Zip Auto Split for Email

Automated script tools that use **7-Zip** to compress files into archives and automatically split them into smaller volumes (15 MiB each by default) for email distribution. Includes archive integrity verification before extraction.

## Features

✅ **7-Zip powered** - Uses 7-Zip for compression with built-in splitting and checksum verification  
✅ **Multi-file selection** - Select multiple files to compress  
✅ **GUI & Terminal modes** - GUI support (Zenity, Kdialog) with terminal fallback  
✅ **Automatic splitting** - Splits archives into 15 MiB volumes (customizable)
✅ **Checksum verification** - Automatic integrity checking during extraction  
✅ **Cross-platform** - PowerShell for Windows, Bash for Linux/Mac  
✅ **Easy merging** - Simple extraction using 7-Zip  

---

## Prerequisites

### For Bash (Linux/Mac)

**Required:**
- `7z` (provided by `7zip` on current Ubuntu releases)
- `bash` (any recent version)
- Standard Unix utilities: `find`, `sort`, `du`, `ls`

**Optional (for GUI):**
- `zenity` (GNOME/GTK-based desktops)
- `kdialog` (KDE desktops)

**Installation:**

```bash
# Current Ubuntu releases
sudo apt install 7zip zenity

# Older Debian/Ubuntu releases may use
sudo apt-get install p7zip-full zenity

# macOS (using Homebrew)
brew install p7zip zenity

# Fedora/RHEL
sudo dnf install p7zip-full zenity

# Arch Linux
sudo pacman -S p7zip zenity
```

### For PowerShell (Windows)

**Required:**
- PowerShell 5.0 or later (included in Windows 10+)
- [7-Zip Desktop](https://www.7-zip.org/) - installed at `C:\Program Files\7-Zip\7z.exe`
  - Or: `choco install 7zip` (if using Chocolatey)
  - Or: `winget install 7zip` (if using Windows Package Manager)

---

## Installation

### Option 1: Clone Repository
```bash
git clone https://github.com/moon200702/sevenzip_auto_split_for_email.git
cd sevenzip_auto_split_for_email
```

### Option 2: Download Individual Scripts
- **Windows:** Download `split-zip-files.ps1`
- **Linux/Mac:** Download `split-zip-files.sh`

---

## Usage

### Windows (PowerShell)

#### Method 1: Run with GUI (Recommended)
```powershell
# Navigate to the script directory
cd C:\Path\To\sevenzip_auto_split_for_email

# Run the script
.\split-zip-files.ps1
```

1. **File Selection Dialog** opens
2. Select files to compress
3. **Folder Selection Dialog** opens
4. Choose output directory
5. Script automatically:
   - Creates ZIP archive
   - Splits into 15 MiB volumes
   - Displays progress and summary

#### Method 2: Run from Command Line
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Supply files, output folder, and volume size without using the GUI
.\split-zip-files.ps1 `
  -Files "C:\Users\me\Documents\report.pdf","C:\Users\me\Documents\notes.txt" `
  -OutputPath "C:\Users\me\Desktop\email-parts" `
  -ChunkSizeMB 15

# Or keep the interactive workflow but use terminal prompts only
.\split-zip-files.ps1 -Terminal
```

#### Common Issues:
- **"cannot be loaded because running scripts is disabled"**
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

### Linux/Mac (Bash)

#### Method 1: Run with GUI (Recommended)
```bash
cd ~/path/to/sevenzip_auto_split_for_email
./split-zip-files.sh
```

1. **File Selection Dialog** opens (if Zenity/Kdialog available)
2. Select files to compress
3. **Folder Selection Dialog** opens
4. Choose output directory
5. Script automatically processes everything

#### Method 2: Terminal-Only Mode
```bash
./split-zip-files.sh
# Follow terminal prompts for file and directory selection
```

#### Method 3: Using Full Path
```bash
/path/to/split-zip-files.sh
```

---

## Output

### File Structure
After running, you'll have 7-Zip volume files like:
```
archive_20240813_143022.zip.001 (15.0 MiB)
archive_20240813_143022.zip.002 (15.0 MiB)
archive_20240813_143022.zip.003 (8.5 MiB)
```

### Chunk Size
- Default volume size: **15 MiB** (customize it for your email provider's limit)
- PowerShell: pass `-ChunkSizeMB`; Bash: edit `CHUNK_SIZE_MB`

---

## Recombining Split Files

### Using 7-Zip (Recommended - Automatic Checksum Verification)

**Windows (interactive script):**
```powershell
.\merge-zip-files.ps1

# You can also pass the first volume or its containing directory directly
.\merge-zip-files.ps1 -InputPath "C:\email-parts\archive_20240813_143022.zip.001"
.\merge-zip-files.ps1 -InputPath "C:\email-parts" -Terminal
```

The script selects one `.zip.001` archive set, checks that its numbered
volumes are continuous, and runs `7z t` before offering three actions: extract
the files, combine the volumes into one ZIP, or test only. GUI file/folder
pickers are used by default, with terminal prompts as a fallback.

You can also right-click the `.zip.001` file and choose **7-Zip → Extract**, or
extract it from PowerShell with `7z x archive_20240813_143022.zip.001`.

**Linux/Mac:**
```bash
# Extract from first part (7z automatically uses other parts)
7z x archive_20240813_143022.zip.001

# Or use the merge script:
./merge-zip-files.sh
```

The Linux merge script opens a file picker for the first `.zip.001` volume,
runs `7z t` to verify every volume, then lets you extract the files, combine the
volumes into one ZIP, or stop after verification. Extraction and combination
use the same GUI output-folder picker with a terminal fallback.

You can also pass either the first volume or its directory directly:

```bash
./merge-zip-files.sh /path/to/archive.zip.001
./merge-zip-files.sh /path/to/volume-directory
```

### Manual Merge (Without 7-Zip)

**Windows (Command Prompt):**
```cmd
copy /b archive.zip.001+archive.zip.002 output.zip
# Then extract with Windows built-in or another tool
```

**Linux/Mac (Terminal):**
```bash
# Merge all parts
cat archive.zip.[0-9][0-9][0-9] > output.zip

# Then extract
unzip output.zip
```

---

## Configuration

### Change Chunk Size

**PowerShell:**
```powershell
# The default is 15 MiB; override it per run with a parameter
.\split-zip-files.ps1 -ChunkSizeMB 20
```

**Bash:**
```bash
# Edit split-zip-files.sh
# Find this line (around line 10):
CHUNK_SIZE_MB=15
# Change to desired size:
CHUNK_SIZE_MB=20  # For 20MB chunks
```

---

## Examples

### Example 1: Compress Multiple Documents
```bash
# Select these files:
# - document1.pdf (5 MB)
# - document2.docx (3 MB)
# - report.xlsx (2 MB)
# Total: 10 MB

# Output:
# archive_20240813_143022.zip.001 (10 MiB)
```

### Example 2: Large Media Files
```bash
# Select these files:
# - video.mp4 (45 MB)
# - backup.tar (20 MB)
# Total: 65 MB

# Output:
# archive_20240813_143022.zip.001 (15 MiB)
# archive_20240813_143022.zip.002 (15 MiB)
# archive_20240813_143022.zip.003 (15 MiB)
# archive_20240813_143022.zip.004 (15 MiB)
# archive_20240813_143022.zip.005 (5 MiB)
```

---

## Features Explained

### GUI Support
- **Zenity** (recommended for GNOME/Linux)
  - Nice file browser dialog
  - Folder selection dialog
  
- **Kdialog** (KDE Plasma)
  - Native KDE file picker
  - Seamless integration
  
- **Terminal Fallback**
  - Works on any system
  - Manual path entry

### Compression Tools
- **7-Zip** (priority)
  - Better compression
  - Faster processing
  - If installed: `C:\Program Files\7-Zip\7z.exe` (Windows)
  - Or available via package manager (Linux/Mac)
  
- **Native Compression** (fallback)
  - No installation needed (Windows)
  - Works on all systems

### Progress Reporting
- File selection confirmation
- Compression progress
- Split chunk progress
- Final summary with file sizes

---

## Troubleshooting

### Issue: "No compression tool found"
**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install zip 7zip

# macOS
brew install p7zip
```

### Issue: "File not found" in terminal mode
**Solution:** Use absolute paths
```bash
/home/user/Documents/myfile.pdf
# Instead of:
myfile.pdf
```

### Issue: GUI dialog doesn't appear
**Solution:** Install zenity or kdialog
```bash
# For Zenity
sudo apt-get install zenity

# For Kdialog (KDE)
sudo apt-get install kdialog
```

### Issue: Split files won't recombine
**Solution:** Ensure all parts are in the same directory with matching names
```bash
# Check file order
ls -la archive_*.zip.[0-9][0-9][0-9]
```

---

## Tips & Best Practices

✅ **Keep output files together** - Store all `.zip.###` files in the same folder
✅ **Verify volume sizes** - Check that the largest volume matches your email limit
✅ **Test before sharing** - Download and test merge before sending to recipient  
✅ **Use descriptive names** - Archive names include timestamp by default  
✅ **Check available space** - Ensure output directory has enough space  

---

## Performance Notes

| Operation | Speed | Notes |
|-----------|-------|-------|
| File selection | Instant | GUI or terminal |
| ZIP creation | Variable | Depends on file size and compression tool |
| ZIP splitting | Fast | ~1-2 seconds per 15MB chunk |
| Recombining | Instant | Simple file concatenation |

---

## Security Considerations

- Scripts do NOT encrypt files (consider using encryption separately)
- Split files contain unencrypted data
- Use secure methods to send files (SFTP, HTTPS, etc.)
- Delete temporary files after successful transfer

---

## FAQ

**Q: Can I split existing ZIP files?**  
A: Modify the script to start from the `split_zip_file()` function

**Q: How do I send split files via email?**  
A: Attach each `.zip.###` volume separately (they're ≤15 MiB each)

**Q: Can recipients recombine files themselves?**  
A: Yes! Include merge instructions from "Recombining Split Files" section

**Q: What's the maximum file size supported?**  
A: Theoretically unlimited (limited by disk space)

**Q: Can I use different chunk sizes?**  
A: Yes. Use `-ChunkSizeMB` in PowerShell, or edit `CHUNK_SIZE_MB` in the Bash script.

---

## License

MIT License - Feel free to use and modify these scripts

## Support

For issues or feature requests:
1. Check Troubleshooting section
2. Review script comments for technical details
3. Visit: https://github.com/moon200702/sevenzip_auto_split_for_email

---

**Created:** 2024  
**Last Updated:** 2024-08-13  
**Author:** moon200702
