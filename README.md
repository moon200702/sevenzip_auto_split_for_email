# 7-Zip Auto Split for Email

Automated script tools that use **7-Zip** to compress files into archives and automatically split them into smaller chunks (15MB each) for email distribution. Includes automatic checksum verification when extracting.

## Features

✅ **7-Zip powered** - Uses 7-Zip for compression with built-in splitting and checksum verification  
✅ **Multi-file selection** - Select multiple files to compress  
✅ **GUI & Terminal modes** - GUI support (Zenity, Kdialog) with terminal fallback  
✅ **Automatic splitting** - Splits archives into 15MB chunks (customizable)  
✅ **Checksum verification** - Automatic integrity checking during extraction  
✅ **Cross-platform** - PowerShell for Windows, Bash for Linux/Mac  
✅ **Easy merging** - Simple extraction using 7-Zip  

---

## Prerequisites

### For Bash (Linux/Mac)

**Required:**
- `7z` (7-Zip command-line tool from p7zip package)
- `bash` (any recent version)
- Standard Unix utilities: `find`, `sort`, `du`, `ls`

**Optional (for GUI):**
- `zenity` (GNOME/GTK-based desktops)
- `kdialog` (KDE desktops)

**Installation:**

```bash
# Ubuntu/Debian
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
   - Splits into 15MB chunks
   - Displays progress and summary

#### Method 2: Run from Command Line
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\split-zip-files.ps1
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
After running, you'll have split files like:
```
archive_20240813_143022.zip.part001 (15.0 MB)
archive_20240813_143022.zip.part002 (15.0 MB)
archive_20240813_143022.zip.part003 (8.5 MB)
```

### Chunk Size
- Default chunk size: **15 MB** (ideal for email attachments)
- Easily customizable by editing `CHUNK_SIZE_MB` in the scripts

---

## Recombining Split Files

### Using 7-Zip (Recommended - Automatic Checksum Verification)

**Windows:**
```powershell
# Right-click on .zip.part001 file and select "7-Zip" → "Extract"
# Or use command line:
7z x archive_20240813_143022.zip.part001
```

**Linux/Mac:**
```bash
# Extract from first part (7z automatically uses other parts)
7z x archive_20240813_143022.zip.part001

# Or use the merge script:
./merge-zip-files.sh
```

### Manual Merge (Without 7-Zip)

**Windows (Command Prompt):**
```cmd
copy /b archive_*.zip.part* output.zip
# Then extract with Windows built-in or another tool
```

**Linux/Mac (Terminal):**
```bash
# Merge all parts
cat archive_*.zip.part* > output.zip

# Then extract
unzip output.zip
```

---

## Configuration

### Change Chunk Size

**PowerShell:**
```powershell
# Edit split-zip-files.ps1
# Find this line (around line 5):
$CHUNK_SIZE_MB = 15
# Change to desired size:
$CHUNK_SIZE_MB = 20  # For 20MB chunks
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
# archive_20240813_143022.part001 (10 MB)
```

### Example 2: Large Media Files
```bash
# Select these files:
# - video.mp4 (45 MB)
# - backup.tar (20 MB)
# Total: 65 MB

# Output:
# archive_20240813_143022.part001 (15 MB)
# archive_20240813_143022.part002 (15 MB)
# archive_20240813_143022.part003 (15 MB)
# archive_20240813_143022.part004 (15 MB)
# archive_20240813_143022.part005 (5 MB)
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
ls -la archive_*.part*
```

---

## Tips & Best Practices

✅ **Keep output files together** - Store all `.part###` files in same folder  
✅ **Verify chunk sizes** - Check that largest chunk is ≤ 15MB  
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
A: Attach each `.part###` file separately (they're ≤15MB each)

**Q: Can recipients recombine files themselves?**  
A: Yes! Include merge instructions from "Recombining Split Files" section

**Q: What's the maximum file size supported?**  
A: Theoretically unlimited (limited by disk space)

**Q: Can I use different chunk sizes?**  
A: Yes! Edit `CHUNK_SIZE_MB` in the script

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