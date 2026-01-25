# Changelog

All notable changes to ProBrowse will be documented in this file.

## [2.6] - 2026-01-25

### Added
- **Change File Type/Aux Type** - Right-click any file on a ProDOS disk to change its file type and auxiliary type
  - Hex input fields with validation
  - Quick-select buttons for common file types (TXT, BIN, SYS, BAS, AWP)
  - Quick-select buttons for common aux types ($0000, $0800, $2000, $4000)
  - Live preview of file type description
- **Help Window** - Built-in help with keyboard shortcuts, supported formats, and troubleshooting tips (Help menu or Cmd+?)
- **NuFX/ShrinkIt Archive Support** - Browse and extract .shk, .sdk, .bxy, and .bny archives
- **UCSD Pascal Support** - Read-only support for UCSD Pascal volumes (.vol files)

### Improved
- DOS 3.3 write support with full file operations
- Better .po and .dsk format detection
- README documentation updates

## [0.8.0] - 2025-01

### Added
- **DOS 3.3 Read/Write Support** - Full support for DOS 3.3 disk images
- **Copy/Cut/Paste** - Context menu with clipboard operations
- **Delete Files** - Delete files and directories from disk images
- **Directory Operations** - Copy and export complete directories with structure

### Fixed
- Directory navigation crash fixes
- Erratic filename display issues
- Column display improvements

## [0.7.0] - 2024-12

### Added
- **Dual-Pane Browser** - Work with two disk images simultaneously
- **Drag & Drop** - Copy files between disk images
- **ProDOS Write Support** - Add, rename, and delete files on ProDOS images
- **Graphics Preview** - View Apple II graphics (HGR, DHGR, SHR, APF) inline
- **File Type Database** - Recognition of 200+ ProDOS file types
- **Date/Time Display** - Shows creation and modification dates
- **Export to Finder** - Extract files to macOS

### Supported Formats
- ProDOS Order (.po)
- DOS Order (.do)
- Universal 2IMG (.2mg)
- Hard Disk Volume (.hdv)
- Generic DSK (.dsk)

---

## Version History Summary

| Version | Date | Highlights |
|---------|------|------------|
| 0.9.0 | 2026-01-25 | Change file type, NuFX/ShrinkIt, UCSD Pascal |
| 0.8.0 | 2025-01 | DOS 3.3 write, copy/paste, delete |
| 0.7.0 | 2024-12 | Initial dual-pane browser release |
