//
//  ProDOSFileTypes.swift
//  ProBrowse
//
//  Complete ProDOS File Type definitions based on Apple Technical Reference
//

import Foundation

struct ProDOSFileTypeInfo {
    let shortName: String
    let description: String
    let category: String
    let icon: String
    let isGraphics: Bool
    
    static func getFileTypeInfo(fileType: UInt8, auxType: Int? = nil) -> ProDOSFileTypeInfo {
        
        func matchesAux(_ expected: Int) -> Bool {
            guard let aux = auxType else { return false }
            return aux == expected
        }
        
        switch fileType {
            
        // MARK: - Graphics Files
            
        case 0x08: // FOT - Graphics
            if let aux = auxType {
                switch aux {
                case 0x4000: return ProDOSFileTypeInfo(shortName: "HGR", description: "Packed Hi-Res", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x4001: return ProDOSFileTypeInfo(shortName: "DHGR", description: "Packed Double Hi-Res", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x8001: return ProDOSFileTypeInfo(shortName: "HGR", description: "Printographer Packed HGR", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x8002: return ProDOSFileTypeInfo(shortName: "DHGR", description: "Printographer Packed DHGR", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x2000: return ProDOSFileTypeInfo(shortName: "HGR", description: "Hi-Res Graphics", category: "Graphics", icon: "🖼️", isGraphics: true)
                default: break
                }
            }
            return ProDOSFileTypeInfo(shortName: "FOT", description: "Apple II Graphics", category: "Graphics", icon: "🖼️", isGraphics: true)
            
        case 0xC0: // PNT - Packed Super Hi-Res
            if let aux = auxType {
                switch aux {
                case 0x0000: return ProDOSFileTypeInfo(shortName: "PNT", description: "Paintworks Packed", category: "Graphics", icon: "🎨", isGraphics: true)
                case 0x0001: return ProDOSFileTypeInfo(shortName: "SHR", description: "Packed Super Hi-Res", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x0002: return ProDOSFileTypeInfo(shortName: "PIC", description: "Apple Preferred Format", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x0003: return ProDOSFileTypeInfo(shortName: "PICT", description: "Packed QuickDraw II PICT", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x8005: return ProDOSFileTypeInfo(shortName: "DGX", description: "DreamGrafix", category: "Graphics", icon: "🎨", isGraphics: true)
                case 0x8006: return ProDOSFileTypeInfo(shortName: "GIF", description: "GIF Image", category: "Graphics", icon: "🖼️", isGraphics: true)
                default: break
                }
            }
            return ProDOSFileTypeInfo(shortName: "PNT", description: "Packed Super Hi-Res", category: "Graphics", icon: "🖼️", isGraphics: true)
            
        case 0xC1: // PIC - Super Hi-Res
            if let aux = auxType {
                switch aux {
                case 0x0000: return ProDOSFileTypeInfo(shortName: "SHR", description: "Super Hi-Res Screen", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x0001: return ProDOSFileTypeInfo(shortName: "PICT", description: "QuickDraw PICT", category: "Graphics", icon: "🖼️", isGraphics: true)
                case 0x0002: return ProDOSFileTypeInfo(shortName: "SHR", description: "SHR 3200 Color", category: "Graphics", icon: "🌈", isGraphics: true)
                case 0x8001: return ProDOSFileTypeInfo(shortName: "IMG", description: "Allison Raw Image", category: "Graphics", icon: "🖼️", isGraphics: true)
                default: break
                }
            }
            return ProDOSFileTypeInfo(shortName: "PIC", description: "Super Hi-Res Picture", category: "Graphics", icon: "🖼️", isGraphics: true)
            
        case 0xC2: return ProDOSFileTypeInfo(shortName: "ANI", description: "Paintworks Animation", category: "Graphics", icon: "🎬", isGraphics: true)
        case 0xC3: return ProDOSFileTypeInfo(shortName: "PAL", description: "Paintworks Palette", category: "Graphics", icon: "🎨", isGraphics: false)
            
        case 0x53: // DRW - Drawing
            if matchesAux(0x8010) {
                return ProDOSFileTypeInfo(shortName: "DRW", description: "AppleWorks GS Graphics", category: "Graphics", icon: "📐", isGraphics: true)
            }
            return ProDOSFileTypeInfo(shortName: "DRW", description: "Drawing", category: "Graphics", icon: "📐", isGraphics: true)
            
        case 0xC5: return ProDOSFileTypeInfo(shortName: "OOG", description: "Object Graphics", category: "Graphics", icon: "📐", isGraphics: true)
            
        // MARK: - Text & Code
            
        case 0x00: return ProDOSFileTypeInfo(shortName: "NON", description: "Unknown", category: "General", icon: "❓", isGraphics: false)
        case 0x01: return ProDOSFileTypeInfo(shortName: "BAD", description: "Bad Blocks", category: "System", icon: "⚠️", isGraphics: false)
        case 0x04: return ProDOSFileTypeInfo(shortName: "TXT", description: "Text File", category: "Text", icon: "📄", isGraphics: false)
        case 0x06: return ProDOSFileTypeInfo(shortName: "BIN", description: "Binary", category: "Code", icon: "⚙️", isGraphics: false)
        case 0x07: return ProDOSFileTypeInfo(shortName: "FNT", description: "Apple III Font", category: "Font", icon: "🔤", isGraphics: false)
            
        case 0x0F: return ProDOSFileTypeInfo(shortName: "DIR", description: "Folder", category: "System", icon: "📁", isGraphics: false)
            
        // MARK: - AppleWorks (8-bit)
            
        case 0x19: return ProDOSFileTypeInfo(shortName: "ADB", description: "AppleWorks Database", category: "Productivity", icon: "🗂️", isGraphics: false)
        case 0x1A: return ProDOSFileTypeInfo(shortName: "AWP", description: "AppleWorks Word Proc", category: "Productivity", icon: "📝", isGraphics: false)
        case 0x1B: return ProDOSFileTypeInfo(shortName: "ASP", description: "AppleWorks Spreadsheet", category: "Productivity", icon: "📊", isGraphics: false)
            
        // MARK: - Apple II Source/Object Code
            
        case 0x2A: return ProDOSFileTypeInfo(shortName: "8SC", description: "Apple II Source Code", category: "Code", icon: "💻", isGraphics: false)
        case 0x2B: return ProDOSFileTypeInfo(shortName: "8OB", description: "Apple II Object Code", category: "Code", icon: "⚙️", isGraphics: false)
        case 0x2E: return ProDOSFileTypeInfo(shortName: "P8C", description: "ProDOS 8 Module", category: "Code", icon: "⚙️", isGraphics: false)
            
        // MARK: - Apple IIgs Productivity
            
        case 0x50: // GWP - GS Word Processing
            if matchesAux(0x8010) {
                return ProDOSFileTypeInfo(shortName: "GWP", description: "AppleWorks GS WP", category: "Productivity", icon: "📝", isGraphics: false)
            }
            return ProDOSFileTypeInfo(shortName: "GWP", description: "GS Word Processing", category: "Productivity", icon: "📝", isGraphics: false)
            
        case 0x51: return ProDOSFileTypeInfo(shortName: "GSS", description: "GS Spreadsheet", category: "Productivity", icon: "📊", isGraphics: false)
        case 0x52: return ProDOSFileTypeInfo(shortName: "GDB", description: "GS Database", category: "Productivity", icon: "🗂️", isGraphics: false)
        case 0x54: return ProDOSFileTypeInfo(shortName: "GDP", description: "Desktop Publishing", category: "Productivity", icon: "📰", isGraphics: false)
            
        // MARK: - System Files
            
        case 0xB0: return ProDOSFileTypeInfo(shortName: "SRC", description: "Apple IIgs Source", category: "Code", icon: "💻", isGraphics: false)
        case 0xB1: return ProDOSFileTypeInfo(shortName: "OBJ", description: "Apple IIgs Object", category: "Code", icon: "⚙️", isGraphics: false)
        case 0xB2: return ProDOSFileTypeInfo(shortName: "LIB", description: "Apple IIgs Library", category: "Code", icon: "📚", isGraphics: false)
        case 0xB3: return ProDOSFileTypeInfo(shortName: "S16", description: "GS/OS Application", category: "System", icon: "⚙️", isGraphics: false)
        case 0xB4: return ProDOSFileTypeInfo(shortName: "RTL", description: "GS/OS Runtime Library", category: "System", icon: "📚", isGraphics: false)
        case 0xB5: return ProDOSFileTypeInfo(shortName: "EXE", description: "Shell Command", category: "System", icon: "⚙️", isGraphics: false)
        case 0xB6: return ProDOSFileTypeInfo(shortName: "PIF", description: "Permanent Init File", category: "System", icon: "⚙️", isGraphics: false)
        case 0xB7: return ProDOSFileTypeInfo(shortName: "TIF", description: "Temporary Init File", category: "System", icon: "⚙️", isGraphics: false)
        case 0xB8: return ProDOSFileTypeInfo(shortName: "NDA", description: "New Desk Accessory", category: "System", icon: "🔧", isGraphics: false)
        case 0xB9: return ProDOSFileTypeInfo(shortName: "CDA", description: "Classic Desk Accessory", category: "System", icon: "🔧", isGraphics: false)
        case 0xBA: return ProDOSFileTypeInfo(shortName: "TOL", description: "Tool", category: "System", icon: "🔧", isGraphics: false)
        case 0xBB: return ProDOSFileTypeInfo(shortName: "DRV", description: "Device Driver", category: "System", icon: "💾", isGraphics: false)
        case 0xBC: return ProDOSFileTypeInfo(shortName: "LDF", description: "Load File", category: "System", icon: "📦", isGraphics: false)
        case 0xBD: return ProDOSFileTypeInfo(shortName: "FST", description: "File System Translator", category: "System", icon: "💾", isGraphics: false)
            
        // MARK: - BASIC Programs
            
        case 0xFA: return ProDOSFileTypeInfo(shortName: "INT", description: "Integer BASIC", category: "Code", icon: "💻", isGraphics: false)
        case 0xFB: return ProDOSFileTypeInfo(shortName: "IVR", description: "Integer Variables", category: "Data", icon: "📄", isGraphics: false)
        case 0xFC: return ProDOSFileTypeInfo(shortName: "BAS", description: "Applesoft BASIC", category: "Code", icon: "💻", isGraphics: false)
        case 0xFD: return ProDOSFileTypeInfo(shortName: "VAR", description: "Applesoft Variables", category: "Data", icon: "📄", isGraphics: false)
        case 0xFE: return ProDOSFileTypeInfo(shortName: "REL", description: "Relocatable", category: "Code", icon: "⚙️", isGraphics: false)
        case 0xFF: return ProDOSFileTypeInfo(shortName: "SYS", description: "ProDOS System", category: "System", icon: "⚙️", isGraphics: false)
            
        // MARK: - Audio & Video
            
        case 0xD5: return ProDOSFileTypeInfo(shortName: "MUS", description: "Music", category: "Audio", icon: "🎵", isGraphics: false)
        case 0xD6: return ProDOSFileTypeInfo(shortName: "INS", description: "Instrument", category: "Audio", icon: "🎹", isGraphics: false)
        case 0xD7: return ProDOSFileTypeInfo(shortName: "MDI", description: "MIDI", category: "Audio", icon: "🎹", isGraphics: false)
        case 0xD8: return ProDOSFileTypeInfo(shortName: "SND", description: "Sound", category: "Audio", icon: "🔊", isGraphics: false)
            
        // MARK: - Archive & Compression
            
        case 0xE0: return ProDOSFileTypeInfo(shortName: "LBR", description: "Library", category: "Archive", icon: "📦", isGraphics: false)
        case 0xE2: return ProDOSFileTypeInfo(shortName: "ATK", description: "AppleTalk Data", category: "Network", icon: "🌐", isGraphics: false)
            
        default:
            return ProDOSFileTypeInfo(shortName: String(format: "$%02X", fileType), description: "Unknown Type", category: "Unknown", icon: "❓", isGraphics: false)
        }
    }
}
