//
//  UTTypeExtensions.swift
//  ProBrowse
//
//  Custom UTType extensions for disk image formats
//

import UniformTypeIdentifiers

extension UTType {
    // ProDOS Ordered disk image
    static var po: UTType {
        UTType(filenameExtension: "po") ?? .data
    }
    
    // 2IMG Universal disk image
    static var twoimg: UTType {
        UTType(filenameExtension: "2mg") ?? .data
    }
    
    // Hard Disk Volume
    static var hdv: UTType {
        UTType(filenameExtension: "hdv") ?? .data
    }
    
    // WOZ disk image (Write-Optimized format)
    static var woz: UTType {
        UTType(filenameExtension: "woz") ?? .data
    }
    
    // DSK disk image (generic)
    static var dsk: UTType {
        UTType(filenameExtension: "dsk") ?? .data
    }
    
    // DOS Ordered disk image
    static var `do`: UTType {
        UTType(filenameExtension: "do") ?? .data
    }
}
