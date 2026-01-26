# Changelog

All notable changes to ProBrowse will be documented in this file.



### Added
- **File Inspector** - Comprehensive file viewer with tabbed interface (Content, Hex, Info)
  - Context menu "Inspect File..." or Cmd+I to open
  - Automatic content type detection based on file type and data analysis
- **BASIC Listing Viewer** - View Applesoft and Integer BASIC programs with syntax highlighting
  - Keywords highlighted in cyan
  - String literals in green
  - REM comments in gray italic
  - Line numbers in yellow
- **Graphics Preview** - Native Apple II graphics decoding
  - Hi-Res (HGR) - 280x192, 6 colors
  - Double Hi-Res (DHGR) - 560x192, 16 colors
  - Super Hi-Res (SHR) - 320x200, 16 colors per scanline
  - 3200-color SHR mode
  - Packed SHR formats: APF (Apple Preferred Format), Paintworks, generic PackBytes
  - Scalable display (1x, 2x, 3x)
- **Hex Dump Viewer** - Professional hex viewer with ASCII sidebar
  - 16 bytes per line with offset column
  - Supports files up to 64KB display
- **Apple IIgs Font Preview** - View bitmap fonts ($C8/FNT files)
  - Sample text rendering with the font
  - Character grid showing all glyphs
  - Font metrics display (height, ascent, descent, etc.)
  - Scalable preview (1x-4x)
- **Apple IIgs Icon Preview** - View icon files ($CA/ICN files)
  - Displays large and small icons with 16-color Apple IIgs palette
  - Transparency mask support with checkerboard background option
  - Shows associated file path patterns
  - Scalable preview (2x-8x)
- **AppleWorks Document Viewer** - View AppleWorks files natively
  - Classic Word Processor ($1A/AWP) with bold, underline, and formatting
  - AppleWorks GS Word Processor ($50/GWP) with WYSIWYG fonts, sizes, and colors
  - Database ($19/ADB) as searchable table with category headers
  - Spreadsheet ($1B/ASP) with cell grid and formulas
  - Full character encoding support including MouseText and Mac OS Roman
- **Teach Document Viewer** - View Apple IIgs Teach files ($50/$5445)
  - WYSIWYG display with fonts, styles, and colors
  - Parses resource fork for style information
  - Paper-like rendering with white background
- **Extended File Support** - Read files with resource forks (storage type 5)
  - Extracts both data fork and resource fork from ProDOS extended files
  - Required for Teach documents and other IIgs applications
- **Native Disk Image Verification** - Verify image integrity without external tools
  - Validates file size, format structure, and 2IMG containers
  - Reports volume name, format, and file count
- **Enhanced File Info Panel** - Detailed metadata display similar to DiskBrowser2
  - Storage type with description (Seedling, Sapling, Tree, etc.)
  - Key pointer, blocks used, EOF in hex and decimal
  - Access flags with permission descriptions (read, write, rename, destroy)
  - Version and min version fields
  - Header pointer for subdirectories

### Removed
- **Cadius dependency** - All operations now use native Swift implementations

### Improved
- Graphics detection now handles BIN files with aux type hints ($2000, $4000)
- Better file type routing for APP ($B3) and PNT ($C0) files
- Cleaner inspector UI with icon-based controls
- **Apple IIgs Icon Rendering** - Fixed icon display to properly handle 4bpp mask format
  - Mask data now correctly interpreted (same size as pixel data, 4bpp format)
  - 0 = transparent, non-zero = opaque (matching CiderPress2 implementation)
  - All standard Finder icon files now render correctly

## [1.0] - 2026-01-25

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
| 2.0 | 2026-01-26 | File Inspector, BASIC viewer, graphics preview, hex dump |
| 1.0 | 2026-01-25 | Change file type, NuFX/ShrinkIt, UCSD Pascal, DOS 3.3 write |
| 0.7.0 | 2024-12 | Initial dual-pane browser release |
