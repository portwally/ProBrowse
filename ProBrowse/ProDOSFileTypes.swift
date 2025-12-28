//
//  ProDOSFileTypes.swift
//  ProBrowse
//
//  Complete ProDOS File Type definitions based on a2infinitum/apple2-filetypes
//  Source: https://github.com/a2infinitum/apple2-filetypes
//

import Foundation

struct ProDOSFileTypeInfo {
    let shortName: String
    let description: String
    let icon: String
    
    static func getFileTypeInfo(fileType: UInt8, auxType: UInt16 = 0) -> ProDOSFileTypeInfo {
        
        // Try to match specific aux type first
        if let info = getSpecificFileType(fileType: fileType, auxType: auxType) {
            return info
        }
        
        // Fall back to generic type
        return getGenericFileType(fileType: fileType)
    }
    
    // MARK: - Specific Aux Type Matches
    
    private static func getSpecificFileType(fileType: UInt8, auxType: UInt16) -> ProDOSFileTypeInfo? {
        switch fileType {
        case 0x08: // FOT - Graphics
            switch auxType {
            case 0x4000: return ProDOSFileTypeInfo(shortName: "HGR", description: "Packed Hi-Res Image", icon: "🖼️")
            case 0x4001: return ProDOSFileTypeInfo(shortName: "DHGR", description: "Packed Double Hi-Res Image", icon: "🖼️")
            case 0x8001: return ProDOSFileTypeInfo(shortName: "HGR", description: "Printographer Packed HGR", icon: "🖼️")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "DHGR", description: "Printographer Packed DHGR", icon: "🖼️")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "HGR", description: "Softdisk Hi-Res image", icon: "🖼️")
            case 0x8004: return ProDOSFileTypeInfo(shortName: "DHGR", description: "Softdisk Double Hi-Res", icon: "🖼️")
            default: return nil
            }
            
        case 0x0B: // WPF - Word Processor
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "WTW", description: "Write This Way document", icon: "📝")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "W&P", description: "Writing & Publishing document", icon: "📝")
            default: return nil
            }
            
        case 0x16: // PFS
            switch auxType {
            case 0x0001: return ProDOSFileTypeInfo(shortName: "PFS", description: "PFS:File document", icon: "📄")
            case 0x0002: return ProDOSFileTypeInfo(shortName: "PFS", description: "PFS:Write document", icon: "📝")
            case 0x0003: return ProDOSFileTypeInfo(shortName: "PFS", description: "PFS:Graph document", icon: "📊")
            case 0x0004: return ProDOSFileTypeInfo(shortName: "PFS", description: "PFS:Plan document", icon: "📊")
            case 0x0016: return ProDOSFileTypeInfo(shortName: "PFS", description: "PFS internal data", icon: "📄")
            default: return nil
            }
            
        case 0x2B: // 8OB - Object Code
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "8OB", description: "GBBS Pro object code", icon: "⚙️")
            default: return nil
            }
            
        case 0x2C: // 8IC - Interpreted Code
            switch auxType {
            case 0x8003: return ProDOSFileTypeInfo(shortName: "APX", description: "APEX Program File", icon: "⚙️")
            default: return nil
            }
            
        case 0x2E: // P8C - ProDOS 8 Code
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "DVX", description: "Davex 8 Command", icon: "⚙️")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "PTP", description: "Point-to-Point drivers", icon: "⚙️")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "PTP", description: "Point-to-Point code", icon: "⚙️")
            default: return nil
            }
            
        case 0x41: // OCR
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "OCR", description: "InWords OCR font table", icon: "🔤")
            default: return nil
            }
            
        case 0x50: // GWP - Word Processor
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "DWR", description: "DeluxeWrite document", icon: "📝")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "PJR", description: "Personal Journal document", icon: "📓")
            case 0x8010: return ProDOSFileTypeInfo(shortName: "AWGS", description: "AppleWorks GS Word Processor", icon: "📝")
            case 0x8011: return ProDOSFileTypeInfo(shortName: "SD", description: "Softdisk issue text", icon: "📝")
            case 0x5445: return ProDOSFileTypeInfo(shortName: "TCH", description: "Teach document", icon: "📚")
            default: return nil
            }
            
        case 0x51: // GSS - Spreadsheet
            switch auxType {
            case 0x8010: return ProDOSFileTypeInfo(shortName: "AWGS", description: "AppleWorks GS Spreadsheet", icon: "📊")
            default: return nil
            }
            
        case 0x52: // GDB - Database
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "GTV", description: "GTv database", icon: "🗄️")
            case 0x8010: return ProDOSFileTypeInfo(shortName: "AWGS", description: "AppleWorks GS Database", icon: "🗄️")
            case 0x8011: return ProDOSFileTypeInfo(shortName: "AWGS", description: "AppleWorks GS DB Template", icon: "🗄️")
            case 0x8013: return ProDOSFileTypeInfo(shortName: "GSAS", description: "GSAS database", icon: "🗄️")
            case 0x8014: return ProDOSFileTypeInfo(shortName: "GSAS", description: "GSAS accounting journals", icon: "💰")
            case 0x8015: return ProDOSFileTypeInfo(shortName: "ADR", description: "Address Manager document", icon: "📇")
            case 0x8016: return ProDOSFileTypeInfo(shortName: "ADR", description: "Address Manager defaults", icon: "📇")
            case 0x8017: return ProDOSFileTypeInfo(shortName: "ADR", description: "Address Manager index", icon: "📇")
            default: return nil
            }
            
        case 0x53: // DRW - Drawing
            switch auxType {
            case 0x8002: return ProDOSFileTypeInfo(shortName: "GDL", description: "Graphic Disk Labeler", icon: "🎨")
            case 0x8010: return ProDOSFileTypeInfo(shortName: "AWGS", description: "AppleWorks GS Graphics", icon: "🎨")
            default: return nil
            }
            
        case 0x54: // GDP - Desktop Publishing
            switch auxType {
            case 0x8002: return ProDOSFileTypeInfo(shortName: "GWR", description: "GraphicWriter document", icon: "📰")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "LBL", description: "Label It document", icon: "🏷️")
            case 0x8010: return ProDOSFileTypeInfo(shortName: "AWGS", description: "AppleWorks GS Page Layout", icon: "📰")
            case 0xDD3E: return ProDOSFileTypeInfo(shortName: "MDL", description: "Medley document", icon: "📰")
            default: return nil
            }
            
        case 0x55: // HMD - Hypermedia
            switch auxType {
            case 0x0001: return ProDOSFileTypeInfo(shortName: "HC", description: "HyperCard IIgs stack", icon: "🗂️")
            case 0x8001: return ProDOSFileTypeInfo(shortName: "TTH", description: "Tutor-Tech document", icon: "📚")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "HS", description: "HyperStudio document", icon: "🗂️")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "NXS", description: "Nexus document", icon: "🗂️")
            case 0x8004: return ProDOSFileTypeInfo(shortName: "HS", description: "HyperSoft stack", icon: "🗂️")
            case 0x8005: return ProDOSFileTypeInfo(shortName: "HS", description: "HyperSoft card", icon: "🗂️")
            case 0x8006: return ProDOSFileTypeInfo(shortName: "HS", description: "HyperSoft external command", icon: "⚙️")
            default: return nil
            }
            
        case 0x56: // EDU - Educational
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "TTH", description: "Tutor-Tech Scores", icon: "📚")
            case 0x8007: return ProDOSFileTypeInfo(shortName: "GRD", description: "GradeBook Data", icon: "📚")
            default: return nil
            }
            
        case 0x57: // STN - Stationery
            switch auxType {
            case 0x8003: return ProDOSFileTypeInfo(shortName: "MW", description: "Music Writer format", icon: "🎵")
            default: return nil
            }
            
        case 0x58: // HLP - Help
            switch auxType {
            case 0x8002: return ProDOSFileTypeInfo(shortName: "DVX", description: "Davex 8 Help File", icon: "❓")
            case 0x8006: return ProDOSFileTypeInfo(shortName: "LOC", description: "Locator help document", icon: "❓")
            case 0x8007: return ProDOSFileTypeInfo(shortName: "PJR", description: "Personal Journal help", icon: "❓")
            case 0x8008: return ProDOSFileTypeInfo(shortName: "HR", description: "Home Refinancer help", icon: "❓")
            default: return nil
            }
            
        case 0x59: // COM - Communications
            switch auxType {
            case 0x8010: return ProDOSFileTypeInfo(shortName: "AWGS", description: "AppleWorks GS Communications", icon: "📡")
            default: return nil
            }
            
        case 0x5A: // CFG - Configuration
            switch auxType {
            case 0x0002: return ProDOSFileTypeInfo(shortName: "RAM", description: "Battery RAM configuration", icon: "⚙️")
            case 0x0003: return ProDOSFileTypeInfo(shortName: "ALN", description: "AutoLaunch preferences", icon: "⚙️")
            case 0x0005: return ProDOSFileTypeInfo(shortName: "GSB", description: "GSBug configuration", icon: "⚙️")
            case 0x8001: return ProDOSFileTypeInfo(shortName: "MTJ", description: "Master Tracks Jr. preferences", icon: "⚙️")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "GWR", description: "GraphicWriter preferences", icon: "⚙️")
            case 0x8005: return ProDOSFileTypeInfo(shortName: "DVX", description: "Davex 8 configuration", icon: "⚙️")
            case 0x8009: return ProDOSFileTypeInfo(shortName: "PTP", description: "Point-to-Point preferences", icon: "⚙️")
            case 0x8010: return ProDOSFileTypeInfo(shortName: "AWGS", description: "AppleWorks GS configuration", icon: "⚙️")
            case 0x801C: return ProDOSFileTypeInfo(shortName: "PP", description: "Platinum Paint preferences", icon: "⚙️")
            default: return nil
            }
            
        case 0x5B: // ANM - Animation
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "CTN", description: "Cartooners movie", icon: "🎬")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "CTN", description: "Cartooners actors", icon: "🎬")
            case 0x8005: return ProDOSFileTypeInfo(shortName: "AK", description: "Arcade King Super document", icon: "🎬")
            case 0x8006: return ProDOSFileTypeInfo(shortName: "AK", description: "Arcade King DHRG document", icon: "🎬")
            case 0x8007: return ProDOSFileTypeInfo(shortName: "DV", description: "DreamVision movie", icon: "🎬")
            default: return nil
            }
            
        case 0x5C: // MUM - Multimedia
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "GTV", description: "GTv multimedia playlist", icon: "🎭")
            default: return nil
            }
            
        case 0x5D: // ENT - Entertainment
            switch auxType {
            case 0x8001: return ProDOSFileTypeInfo(shortName: "SR", description: "Solitaire Royale document", icon: "🎮")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "BF", description: "BattleFront scenario", icon: "🎮")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "BF", description: "BattleFront saved game", icon: "🎮")
            case 0x8004: return ProDOSFileTypeInfo(shortName: "GA", description: "Gold of the Americas game", icon: "🎮")
            case 0x8006: return ProDOSFileTypeInfo(shortName: "BJT", description: "Blackjack Tutor document", icon: "🎮")
            default: return nil
            }
            
        case 0x5E: // DVU - Development
            switch auxType {
            case 0x0001: return ProDOSFileTypeInfo(shortName: "RSC", description: "Resource file", icon: "🔧")
            case 0x8001: return ProDOSFileTypeInfo(shortName: "ORC", description: "ORCA/Disassembler template", icon: "🔧")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "DSM", description: "DesignMaster document", icon: "🔧")
            default: return nil
            }
            
        case 0x5F: // FIN - Financial
            switch auxType {
            case 0x8002: return ProDOSFileTypeInfo(shortName: "HR", description: "Home Refinancer document", icon: "💰")
            default: return nil
            }
            
        case 0xB0: // SRC - Source Code
            switch auxType {
            case 0x0001: return ProDOSFileTypeInfo(shortName: "TXT", description: "APW Text file", icon: "📄")
            case 0x0003: return ProDOSFileTypeInfo(shortName: "ASM", description: "APW 65816 Assembly source", icon: "📄")
            case 0x0005: return ProDOSFileTypeInfo(shortName: "PAS", description: "ORCA/Pascal source code", icon: "📄")
            case 0x0006: return ProDOSFileTypeInfo(shortName: "CMD", description: "APW command file", icon: "⚙️")
            case 0x0008: return ProDOSFileTypeInfo(shortName: "C", description: "ORCA/C source code", icon: "📄")
            case 0x0009: return ProDOSFileTypeInfo(shortName: "LNK", description: "APW Linker command file", icon: "⚙️")
            case 0x000A: return ProDOSFileTypeInfo(shortName: "C", description: "APW C source code", icon: "📄")
            case 0x000C: return ProDOSFileTypeInfo(shortName: "CMD", description: "ORCA/Desktop command file", icon: "⚙️")
            case 0x0015: return ProDOSFileTypeInfo(shortName: "REZ", description: "APW Rez source file", icon: "📄")
            case 0x0017: return ProDOSFileTypeInfo(shortName: "INS", description: "Installer script", icon: "⚙️")
            case 0x001E: return ProDOSFileTypeInfo(shortName: "PAS", description: "TML Pascal source code", icon: "📄")
            case 0x0116: return ProDOSFileTypeInfo(shortName: "SCR", description: "ORCA/Disassembler script", icon: "📄")
            case 0x0503: return ProDOSFileTypeInfo(shortName: "ASM", description: "SDE Assembler source code", icon: "📄")
            case 0x0506: return ProDOSFileTypeInfo(shortName: "CMD", description: "SDE command script", icon: "⚙️")
            case 0x0601: return ProDOSFileTypeInfo(shortName: "NFL", description: "Nifty List data", icon: "📄")
            case 0x0719: return ProDOSFileTypeInfo(shortName: "PS", description: "PostScript file", icon: "📄")
            default: return nil
            }
            
        case 0xBB: // DVR - Device Driver
            switch auxType {
            case 0x7F01: return ProDOSFileTypeInfo(shortName: "GTV", description: "GTv videodisc serial driver", icon: "💿")
            case 0x7F02: return ProDOSFileTypeInfo(shortName: "GTV", description: "GTv videodisc game port driver", icon: "💿")
            default: return nil
            }
            
        case 0xBC: // LDF - Load File
            switch auxType {
            case 0x4001: return ProDOSFileTypeInfo(shortName: "NFL", description: "Nifty List Module", icon: "⚙️")
            case 0x4002: return ProDOSFileTypeInfo(shortName: "SI", description: "Super Info module", icon: "⚙️")
            case 0x4004: return ProDOSFileTypeInfo(shortName: "TWL", description: "Twilight document", icon: "⚙️")
            case 0x4007: return ProDOSFileTypeInfo(shortName: "HS", description: "HyperStudio New Button Action", icon: "⚙️")
            case 0x4008: return ProDOSFileTypeInfo(shortName: "HS", description: "HyperStudio Screen Transition", icon: "⚙️")
            case 0x4009: return ProDOSFileTypeInfo(shortName: "DGX", description: "DreamGrafix module", icon: "⚙️")
            case 0x400A: return ProDOSFileTypeInfo(shortName: "HS", description: "HyperStudio Extra utility", icon: "⚙️")
            case 0x400F: return ProDOSFileTypeInfo(shortName: "HP", description: "HardPressed compression module", icon: "⚙️")
            default: return nil
            }
            
        case 0xC0: // PNT - Packed Super Hi-Res
            switch auxType {
            case 0x0000: return ProDOSFileTypeInfo(shortName: "PNT", description: "Paintworks Packed picture", icon: "🎨")
            case 0x0001: return ProDOSFileTypeInfo(shortName: "SHR", description: "Packed Super Hi-Res Image", icon: "🖼️")
            case 0x0002: return ProDOSFileTypeInfo(shortName: "APF", description: "Apple Preferred Format picture", icon: "🖼️")
            case 0x0003: return ProDOSFileTypeInfo(shortName: "PICT", description: "Packed QuickDraw II PICT file", icon: "🖼️")
            case 0x8001: return ProDOSFileTypeInfo(shortName: "GTV", description: "GTv background image", icon: "🖼️")
            case 0x8005: return ProDOSFileTypeInfo(shortName: "DGX", description: "DreamGrafix document", icon: "🎨")
            case 0x8006: return ProDOSFileTypeInfo(shortName: "GIF", description: "GIF document", icon: "🖼️")
            default: return nil
            }
            
        case 0xC1: // PIC - Super Hi-Res
            switch auxType {
            case 0x0000: return ProDOSFileTypeInfo(shortName: "SHR", description: "Super Hi-Res Screen image", icon: "🖼️")
            case 0x0001: return ProDOSFileTypeInfo(shortName: "PICT", description: "QuickDraw PICT file", icon: "🖼️")
            case 0x0002: return ProDOSFileTypeInfo(shortName: "SHR", description: "Super Hi-Res 3200 color image", icon: "🖼️")
            case 0x8001: return ProDOSFileTypeInfo(shortName: "ALL", description: "Allison raw image doc", icon: "🖼️")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "THN", description: "ThunderScan image doc", icon: "🖼️")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "DGX", description: "DreamGrafix document", icon: "🎨")
            default: return nil
            }
            
        case 0xC5: // OOG - Object-Oriented Graphics
            switch auxType {
            case 0x8000: return ProDOSFileTypeInfo(shortName: "DP", description: "Draw Plus document", icon: "🎨")
            case 0xC000: return ProDOSFileTypeInfo(shortName: "DYOH", description: "DYOH Architecture doc", icon: "🏗️")
            case 0xC001: return ProDOSFileTypeInfo(shortName: "DYOH", description: "DYOH predrawn objects", icon: "🏗️")
            case 0xC002: return ProDOSFileTypeInfo(shortName: "DYOH", description: "DYOH custom objects", icon: "🏗️")
            case 0xC003: return ProDOSFileTypeInfo(shortName: "DYOH", description: "DYOH clipboard", icon: "🏗️")
            case 0xC006: return ProDOSFileTypeInfo(shortName: "DYOH", description: "DYOH Landscape Document", icon: "🏗️")
            case 0xC007: return ProDOSFileTypeInfo(shortName: "PYW", description: "PyWare Document", icon: "🎨")
            case 0xC008: return ProDOSFileTypeInfo(shortName: "AN3", description: "Animasia 3-D Project", icon: "🎬")
            default: return nil
            }
            
        case 0xC8: // FON - Font
            switch auxType {
            case 0x0000: return ProDOSFileTypeInfo(shortName: "FON", description: "QuickDraw II Font", icon: "🔤")
            case 0x0001: return ProDOSFileTypeInfo(shortName: "TTF", description: "TrueType font", icon: "🔤")
            default: return nil
            }
            
        case 0xD5: // MUS - Music
            switch auxType {
            case 0x0000: return ProDOSFileTypeInfo(shortName: "MCS", description: "Music Construction Set song", icon: "🎵")
            case 0x0001: return ProDOSFileTypeInfo(shortName: "MID", description: "MIDI Synth sequence", icon: "🎵")
            case 0x0007: return ProDOSFileTypeInfo(shortName: "SS", description: "SoundSmith document", icon: "🎵")
            case 0x0008: return ProDOSFileTypeInfo(shortName: "NTP", description: "NinjaTrackerPlus sequence", icon: "🎵")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "DT", description: "Diversi-Tune sequence", icon: "🎵")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "MTJ", description: "Master Tracks Jr. sequence", icon: "🎵")
            case 0x8005: return ProDOSFileTypeInfo(shortName: "AK", description: "Arcade King Super music", icon: "🎵")
            default: return nil
            }
            
        case 0xD6: // INS - Instrument
            switch auxType {
            case 0x0000: return ProDOSFileTypeInfo(shortName: "MCS", description: "Music Construction Set instrument", icon: "🎹")
            case 0x0001: return ProDOSFileTypeInfo(shortName: "MID", description: "MIDI Synth instrument", icon: "🎹")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "DT", description: "Diversi-Tune instrument", icon: "🎹")
            default: return nil
            }
            
        case 0xD7: // MDI - MIDI
            switch auxType {
            case 0x0000: return ProDOSFileTypeInfo(shortName: "MID", description: "MIDI standard data", icon: "🎵")
            default: return nil
            }
            
        case 0xD8: // SND - Sound
            switch auxType {
            case 0x0000: return ProDOSFileTypeInfo(shortName: "AIFF", description: "Audio IFF document", icon: "🔊")
            case 0x0001: return ProDOSFileTypeInfo(shortName: "AIFC", description: "AIFF-C document", icon: "🔊")
            case 0x0002: return ProDOSFileTypeInfo(shortName: "ASIF", description: "ASIF instrument", icon: "🔊")
            case 0x0003: return ProDOSFileTypeInfo(shortName: "SND", description: "Sound resource file", icon: "🔊")
            case 0x0004: return ProDOSFileTypeInfo(shortName: "MID", description: "MIDI Synth wave data", icon: "🔊")
            case 0x0005: return ProDOSFileTypeInfo(shortName: "CDDA", description: "CD Digital Audio Track", icon: "💿")
            case 0x0006: return ProDOSFileTypeInfo(shortName: "CDDD", description: "CD Digital Data Track", icon: "💿")
            case 0x8001: return ProDOSFileTypeInfo(shortName: "HS", description: "HyperStudio sound", icon: "🔊")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "AK", description: "Arcade King Super sound", icon: "🔊")
            case 0x8003: return ProDOSFileTypeInfo(shortName: "SO", description: "SoundOff! sound bank", icon: "🔊")
            default: return nil
            }
            
        case 0xDB: // DBM - DB Master
            switch auxType {
            case 0x0001: return ProDOSFileTypeInfo(shortName: "DBM", description: "DB Master document", icon: "🗄️")
            default: return nil
            }
            
        case 0xE0: // LBR - Library/Archive
            switch auxType {
            case 0x0000: return ProDOSFileTypeInfo(shortName: "ALU", description: "ALU library", icon: "📦")
            case 0x0001: return ProDOSFileTypeInfo(shortName: "AS", description: "AppleSingle File", icon: "📦")
            case 0x0002: return ProDOSFileTypeInfo(shortName: "AD", description: "AppleDouble Header File", icon: "📦")
            case 0x0003: return ProDOSFileTypeInfo(shortName: "AD", description: "AppleDouble Data File", icon: "📦")
            case 0x0005: return ProDOSFileTypeInfo(shortName: "DC", description: "DiskCopy disk image", icon: "💾")
            case 0x8000: return ProDOSFileTypeInfo(shortName: "BNY", description: "Binary II File", icon: "📦")
            case 0x8001: return ProDOSFileTypeInfo(shortName: "ACU", description: "AppleLink ACU document", icon: "📦")
            case 0x8002: return ProDOSFileTypeInfo(shortName: "SHK", description: "ShrinkIt (NuFX) document", icon: "📦")
            case 0x8004: return ProDOSFileTypeInfo(shortName: "DVX", description: "Davex archived volume", icon: "📦")
            case 0x8006: return ProDOSFileTypeInfo(shortName: "EZB", description: "EZ Backup Saveset doc", icon: "📦")
            case 0x8007: return ProDOSFileTypeInfo(shortName: "ELS", description: "ELS DOS 3.3 volume", icon: "💾")
            case 0x8009: return ProDOSFileTypeInfo(shortName: "UW", description: "UtilityWorks document", icon: "📦")
            case 0x800A: return ProDOSFileTypeInfo(shortName: "REP", description: "Replicator document", icon: "📦")
            case 0x800D: return ProDOSFileTypeInfo(shortName: "HP", description: "HardPressed (data fork)", icon: "📦")
            case 0x800E: return ProDOSFileTypeInfo(shortName: "HP", description: "HardPressed (rsrc fork)", icon: "📦")
            case 0x800F: return ProDOSFileTypeInfo(shortName: "HP", description: "HardPressed (both forks)", icon: "📦")
            default: return nil
            }
            
        case 0xE2: // ATK - AppleTalk
            switch auxType {
            case 0xFFFF: return ProDOSFileTypeInfo(shortName: "EM", description: "EasyMount document", icon: "🌐")
            default: return nil
            }
            
        default:
            return nil
        }
    }
    
    // MARK: - Generic File Types
    
    private static func getGenericFileType(fileType: UInt8) -> ProDOSFileTypeInfo {
        switch fileType {
        case 0x00: return ProDOSFileTypeInfo(shortName: "NON", description: "Unknown", icon: "❓")
        case 0x01: return ProDOSFileTypeInfo(shortName: "BAD", description: "Bad blocks", icon: "⚠️")
        case 0x02: return ProDOSFileTypeInfo(shortName: "PCD", description: "Pascal code", icon: "📄")
        case 0x03: return ProDOSFileTypeInfo(shortName: "PTX", description: "Pascal text", icon: "📄")
        case 0x04: return ProDOSFileTypeInfo(shortName: "TXT", description: "ASCII text", icon: "📄")
        case 0x05: return ProDOSFileTypeInfo(shortName: "PDA", description: "Pascal data", icon: "📄")
        case 0x06: return ProDOSFileTypeInfo(shortName: "BIN", description: "Binary", icon: "🔢")
        case 0x07: return ProDOSFileTypeInfo(shortName: "FNT", description: "Apple /// Font", icon: "🔤")
        case 0x08: return ProDOSFileTypeInfo(shortName: "FOT", description: "Apple II Graphics", icon: "🖼️")
        case 0x09: return ProDOSFileTypeInfo(shortName: "BA3", description: "Apple /// BASIC program", icon: "📄")
        case 0x0A: return ProDOSFileTypeInfo(shortName: "DA3", description: "Apple /// BASIC data", icon: "📄")
        case 0x0B: return ProDOSFileTypeInfo(shortName: "WPF", description: "Word Processor", icon: "📝")
        case 0x0C: return ProDOSFileTypeInfo(shortName: "SOS", description: "Apple /// SOS System", icon: "⚙️")
        case 0x0F: return ProDOSFileTypeInfo(shortName: "DIR", description: "Folder", icon: "📁")
        case 0x10: return ProDOSFileTypeInfo(shortName: "RPD", description: "Apple /// RPS data", icon: "📄")
        case 0x11: return ProDOSFileTypeInfo(shortName: "RPI", description: "Apple /// RPS index", icon: "📄")
        case 0x12: return ProDOSFileTypeInfo(shortName: "AFD", description: "Apple /// AppleFile discard", icon: "📄")
        case 0x13: return ProDOSFileTypeInfo(shortName: "AFM", description: "Apple /// AppleFile model", icon: "📄")
        case 0x14: return ProDOSFileTypeInfo(shortName: "AFR", description: "Apple /// AppleFile report", icon: "📄")
        case 0x15: return ProDOSFileTypeInfo(shortName: "SCL", description: "Apple /// screen library", icon: "📄")
        case 0x16: return ProDOSFileTypeInfo(shortName: "PFS", description: "PFS document", icon: "📄")
        case 0x19: return ProDOSFileTypeInfo(shortName: "ADB", description: "AppleWorks Data Base", icon: "🗄️")
        case 0x1A: return ProDOSFileTypeInfo(shortName: "AWP", description: "AppleWorks Word Processor", icon: "📝")
        case 0x1B: return ProDOSFileTypeInfo(shortName: "ASP", description: "AppleWorks Spreadsheet", icon: "📊")
        case 0x20: return ProDOSFileTypeInfo(shortName: "TDM", description: "Desktop Manager document", icon: "📄")
        case 0x21: return ProDOSFileTypeInfo(shortName: "IPS", description: "Instant Pascal source", icon: "📄")
        case 0x22: return ProDOSFileTypeInfo(shortName: "UPV", description: "UCSD Pascal Volume", icon: "💾")
        case 0x29: return ProDOSFileTypeInfo(shortName: "DIC", description: "Apple /// SOS Dictionary", icon: "📕")
        case 0x2A: return ProDOSFileTypeInfo(shortName: "8SC", description: "Apple II Source Code", icon: "📄")
        case 0x2B: return ProDOSFileTypeInfo(shortName: "8OB", description: "Apple II Object Code", icon: "⚙️")
        case 0x2C: return ProDOSFileTypeInfo(shortName: "8IC", description: "Apple II Interpreted Code", icon: "⚙️")
        case 0x2D: return ProDOSFileTypeInfo(shortName: "8LD", description: "Apple II Language Data", icon: "📄")
        case 0x2E: return ProDOSFileTypeInfo(shortName: "P8C", description: "ProDOS 8 code module", icon: "⚙️")
        case 0x40: return ProDOSFileTypeInfo(shortName: "DIC", description: "Dictionary file", icon: "📕")
        case 0x41: return ProDOSFileTypeInfo(shortName: "OCR", description: "OCR data", icon: "🔤")
        case 0x42: return ProDOSFileTypeInfo(shortName: "FTD", description: "File Type Descriptors", icon: "📄")
        case 0x43: return ProDOSFileTypeInfo(shortName: "PRD", description: "Peripheral data", icon: "⚙️")
        case 0x50: return ProDOSFileTypeInfo(shortName: "GWP", description: "Apple IIgs Word Processor", icon: "📝")
        case 0x51: return ProDOSFileTypeInfo(shortName: "GSS", description: "Apple IIgs Spreadsheet", icon: "📊")
        case 0x52: return ProDOSFileTypeInfo(shortName: "GDB", description: "Apple IIgs Data Base", icon: "🗄️")
        case 0x53: return ProDOSFileTypeInfo(shortName: "DRW", description: "Drawing", icon: "🎨")
        case 0x54: return ProDOSFileTypeInfo(shortName: "GDP", description: "Desktop Publishing", icon: "📰")
        case 0x55: return ProDOSFileTypeInfo(shortName: "HMD", description: "Hypermedia", icon: "🗂️")
        case 0x56: return ProDOSFileTypeInfo(shortName: "EDU", description: "Educational Data", icon: "📚")
        case 0x57: return ProDOSFileTypeInfo(shortName: "STN", description: "Stationery", icon: "📄")
        case 0x58: return ProDOSFileTypeInfo(shortName: "HLP", description: "Help File", icon: "❓")
        case 0x59: return ProDOSFileTypeInfo(shortName: "COM", description: "Communications File", icon: "📡")
        case 0x5A: return ProDOSFileTypeInfo(shortName: "CFG", description: "Configuration file", icon: "⚙️")
        case 0x5B: return ProDOSFileTypeInfo(shortName: "ANM", description: "Animation file", icon: "🎬")
        case 0x5C: return ProDOSFileTypeInfo(shortName: "MUM", description: "Multimedia document", icon: "🎭")
        case 0x5D: return ProDOSFileTypeInfo(shortName: "ENT", description: "Game/Entertainment", icon: "🎮")
        case 0x5E: return ProDOSFileTypeInfo(shortName: "DVU", description: "Development utility", icon: "🔧")
        case 0x5F: return ProDOSFileTypeInfo(shortName: "FIN", description: "Financial document", icon: "💰")
        case 0x6B: return ProDOSFileTypeInfo(shortName: "BIO", description: "PC Transporter BIOS", icon: "💿")
        case 0x6D: return ProDOSFileTypeInfo(shortName: "TDR", description: "PC Transporter driver", icon: "💿")
        case 0x6E: return ProDOSFileTypeInfo(shortName: "PRE", description: "PC Transporter pre-boot", icon: "💿")
        case 0x6F: return ProDOSFileTypeInfo(shortName: "HDV", description: "PC Transporter volume", icon: "💿")
        case 0xA0: return ProDOSFileTypeInfo(shortName: "WP", description: "WordPerfect document", icon: "📝")
        case 0xAB: return ProDOSFileTypeInfo(shortName: "GSB", description: "Apple IIgs BASIC program", icon: "📄")
        case 0xAC: return ProDOSFileTypeInfo(shortName: "TDF", description: "Apple IIgs BASIC TDF", icon: "📄")
        case 0xAD: return ProDOSFileTypeInfo(shortName: "BDF", description: "Apple IIgs BASIC data", icon: "📄")
        case 0xB0: return ProDOSFileTypeInfo(shortName: "SRC", description: "Apple IIgs source code", icon: "📄")
        case 0xB1: return ProDOSFileTypeInfo(shortName: "OBJ", description: "Apple IIgs object code", icon: "⚙️")
        case 0xB2: return ProDOSFileTypeInfo(shortName: "LIB", description: "Apple IIgs Library file", icon: "📚")
        case 0xB3: return ProDOSFileTypeInfo(shortName: "S16", description: "GS/OS application", icon: "🖥️")
        case 0xB4: return ProDOSFileTypeInfo(shortName: "RTL", description: "GS/OS Run-Time Library", icon: "📚")
        case 0xB5: return ProDOSFileTypeInfo(shortName: "EXE", description: "GS/OS Shell application", icon: "⚙️")
        case 0xB6: return ProDOSFileTypeInfo(shortName: "PIF", description: "Permanent init file", icon: "⚙️")
        case 0xB7: return ProDOSFileTypeInfo(shortName: "TIF", description: "Temporary init file", icon: "⚙️")
        case 0xB8: return ProDOSFileTypeInfo(shortName: "NDA", description: "New desk accessory", icon: "🔧")
        case 0xB9: return ProDOSFileTypeInfo(shortName: "CDA", description: "Classic desk accessory", icon: "🔧")
        case 0xBA: return ProDOSFileTypeInfo(shortName: "TOL", description: "Tool", icon: "🔧")
        case 0xBB: return ProDOSFileTypeInfo(shortName: "DVR", description: "Device Driver", icon: "⚙️")
        case 0xBC: return ProDOSFileTypeInfo(shortName: "LDF", description: "Load file (generic)", icon: "⚙️")
        case 0xBD: return ProDOSFileTypeInfo(shortName: "FST", description: "File System Translator", icon: "⚙️")
        case 0xBF: return ProDOSFileTypeInfo(shortName: "DOC", description: "GS/OS document", icon: "📄")
        case 0xC0: return ProDOSFileTypeInfo(shortName: "PNT", description: "Packed Super Hi-Res", icon: "🎨")
        case 0xC1: return ProDOSFileTypeInfo(shortName: "PIC", description: "Super Hi-Res picture", icon: "🖼️")
        case 0xC2: return ProDOSFileTypeInfo(shortName: "ANI", description: "Paintworks animation", icon: "🎬")
        case 0xC3: return ProDOSFileTypeInfo(shortName: "PAL", description: "Paintworks palette", icon: "🎨")
        case 0xC5: return ProDOSFileTypeInfo(shortName: "OOG", description: "Object-oriented graphics", icon: "🎨")
        case 0xC6: return ProDOSFileTypeInfo(shortName: "SCR", description: "Script", icon: "📄")
        case 0xC7: return ProDOSFileTypeInfo(shortName: "CDV", description: "Control Panel document", icon: "⚙️")
        case 0xC8: return ProDOSFileTypeInfo(shortName: "FON", description: "Font", icon: "🔤")
        case 0xC9: return ProDOSFileTypeInfo(shortName: "FND", description: "Finder data", icon: "🗂️")
        case 0xCA: return ProDOSFileTypeInfo(shortName: "ICN", description: "Icons", icon: "🖼️")
        case 0xD5: return ProDOSFileTypeInfo(shortName: "MUS", description: "Music sequence", icon: "🎵")
        case 0xD6: return ProDOSFileTypeInfo(shortName: "INS", description: "Instrument", icon: "🎹")
        case 0xD7: return ProDOSFileTypeInfo(shortName: "MDI", description: "MIDI data", icon: "🎵")
        case 0xD8: return ProDOSFileTypeInfo(shortName: "SND", description: "Sampled sound", icon: "🔊")
        case 0xDB: return ProDOSFileTypeInfo(shortName: "DBM", description: "DB Master document", icon: "🗄️")
        case 0xE0: return ProDOSFileTypeInfo(shortName: "LBR", description: "Archival library", icon: "📦")
        case 0xE2: return ProDOSFileTypeInfo(shortName: "ATK", description: "AppleTalk data", icon: "🌐")
        case 0xEE: return ProDOSFileTypeInfo(shortName: "R16", description: "EDASM 816 relocatable", icon: "⚙️")
        case 0xEF: return ProDOSFileTypeInfo(shortName: "PAS", description: "Pascal area", icon: "📄")
        case 0xF0: return ProDOSFileTypeInfo(shortName: "CMD", description: "BASIC command", icon: "⚙️")
        case 0xF1: return ProDOSFileTypeInfo(shortName: "U01", description: "User #1", icon: "📄")
        case 0xF2: return ProDOSFileTypeInfo(shortName: "U02", description: "User #2", icon: "📄")
        case 0xF3: return ProDOSFileTypeInfo(shortName: "U03", description: "User #3", icon: "📄")
        case 0xF4: return ProDOSFileTypeInfo(shortName: "U04", description: "User #4", icon: "📄")
        case 0xF5: return ProDOSFileTypeInfo(shortName: "U05", description: "User #5", icon: "📄")
        case 0xF6: return ProDOSFileTypeInfo(shortName: "U06", description: "User #6", icon: "📄")
        case 0xF7: return ProDOSFileTypeInfo(shortName: "U07", description: "User #7", icon: "📄")
        case 0xF8: return ProDOSFileTypeInfo(shortName: "U08", description: "User #8", icon: "📄")
        case 0xF9: return ProDOSFileTypeInfo(shortName: "OS", description: "GS/OS System file", icon: "⚙️")
        case 0xFA: return ProDOSFileTypeInfo(shortName: "INT", description: "Integer BASIC program", icon: "📄")
        case 0xFB: return ProDOSFileTypeInfo(shortName: "IVR", description: "Integer BASIC variables", icon: "📄")
        case 0xFC: return ProDOSFileTypeInfo(shortName: "BAS", description: "AppleSoft BASIC program", icon: "📄")
        case 0xFD: return ProDOSFileTypeInfo(shortName: "VAR", description: "AppleSoft BASIC variables", icon: "📄")
        case 0xFE: return ProDOSFileTypeInfo(shortName: "REL", description: "Relocatable code", icon: "⚙️")
        case 0xFF: return ProDOSFileTypeInfo(shortName: "SYS", description: "ProDOS 8 application", icon: "⚙️")
            
        default:
            return ProDOSFileTypeInfo(shortName: String(format: "$%02X", fileType), description: "Unknown Type", icon: "❓")
        }
    }
}
