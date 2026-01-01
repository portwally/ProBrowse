# ProBrowse

**⚠️ BETA VERSION - USE AT YOUR OWN RISK ⚠️**

This is an early beta version under active development. It may contain bugs that could corrupt your disk images. **Always backup your disk images before using ProBrowse!**

---
<img width="1561" height="820" alt="Bildschirmfoto 2025-12-27 um 20 02 29" src="https://github.com/user-attachments/assets/19469707-805b-4c16-9fb5-c9f4bc5179f8" />

## What is ProBrowse?

ProBrowse is a modern macOS dual-pane file manager for Apple II disk images, bringing vintage computing into the 21st century.

### Features

✅ **Dual-Pane Browser** - Work with two disk images simultaneously  
✅ **Native ProDOS Support** - Read and write ProDOS disk images natively in Swift  
✅ **Drag & Drop** - Copy files between disk images with ease  
✅ **Complete File Type Database** - Recognizes 200+ ProDOS file types with proper names  
✅ **Graphics Preview** - View Apple II graphics (HGR, DHGR, SHR, APF) directly  
✅ **Date/Time Support** - Displays creation and modification dates from ProDOS  
✅ **Modern UI** - Clean SwiftUI interface with resizable columns  
✅ **Export Capability** - Extract files to your Mac  

### Supported Formats

- **Disk Images**: `.po`, `.2mg` (ProDOS format)
- **Graphics**: HGR, DHGR, SHR (Super Hi-Res), APF (Apple Preferred Format)
- **File Systems**: ProDOS (read/write), DOS 3.3 (read-only)

### Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

### Current Limitations

- Subdirectory copying not yet fully implemented
- No DOS 3.3 write support (read-only)
- Beta quality - expect bugs!

---

## Quick Start

1. Open two disk images (left and right panes)
2. Browse files with full ProDOS directory support
3. Drag & drop files between images
4. Export files to your Mac
5. View Apple II graphics inline

## Building

Requires Xcode 15+ and macOS 14.0+

```bash
open ProBrowse.xcodeproj
```

---

## Development

Built with Swift and SwiftUI for modern macOS.

**License**: MIT

**Status**: Active development - contributions welcome!

---

**Remember: Always backup your disk images before using beta software!**


[![Downloads](https://img.shields.io/github/downloads/portwally/ProBrowse/total?style=flat&color=0d6efd)](https://github.com/portwally/ProBrowse/releases)
[![Stars](https://img.shields.io/github/stars/portwally/ProBrowse?style=flat&color=f1c40f)](https://github.com/portwally/ProBrowse/stargazers)
[![Forks](https://img.shields.io/github/forks/portwally/ProBrowse?style=flat&color=2ecc71)](https://github.com/portwally/ProBrowse/network/members)
