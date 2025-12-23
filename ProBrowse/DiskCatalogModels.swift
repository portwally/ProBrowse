//
//  DiskCatalogModels.swift
//  ProBrowse
//
//  Data models for disk catalog browsing
//

import Foundation

// MARK: - Disk Catalog Entry

struct DiskCatalogEntry: Identifiable, Codable {
    let id: UUID
    let name: String
    let fileType: UInt8
    let fileTypeString: String
    let size: Int
    let blocks: Int?
    let loadAddress: Int?
    let length: Int?
    let data: Data
    let isImage: Bool
    let isDirectory: Bool
    let children: [DiskCatalogEntry]?
    
    init(id: UUID = UUID(), name: String, fileType: UInt8, fileTypeString: String, size: Int, blocks: Int?, loadAddress: Int?, length: Int?, data: Data, isImage: Bool, isDirectory: Bool, children: [DiskCatalogEntry]?) {
        self.id = id
        self.name = name
        self.fileType = fileType
        self.fileTypeString = fileTypeString
        self.size = size
        self.blocks = blocks
        self.loadAddress = loadAddress
        self.length = length
        self.data = data
        self.isImage = isImage
        self.isDirectory = isDirectory
        self.children = children
    }
    
    var sizeString: String {
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }
    
    var fileTypeInfo: ProDOSFileTypeInfo {
        return ProDOSFileTypeInfo.getFileTypeInfo(fileType: fileType, auxType: loadAddress)
    }
    
    var icon: String {
        if isDirectory { return "📁" }
        return fileTypeInfo.icon
    }
    
    var typeDescription: String {
        if isDirectory { return "Folder" }
        return fileTypeInfo.shortName
    }
}

// MARK: - Disk Catalog

struct DiskCatalog: Codable {
    let diskName: String
    let diskFormat: String
    let diskSize: Int
    let entries: [DiskCatalogEntry]
    
    var rootEntries: [DiskCatalogEntry] {
        return entries
    }
    
    var totalFiles: Int {
        countFiles(in: entries)
    }
    
    var imageFiles: Int {
        countImages(in: entries)
    }
    
    var allEntries: [DiskCatalogEntry] {
        return flattenEntries(entries)
    }
    
    private func countFiles(in entries: [DiskCatalogEntry]) -> Int {
        var count = 0
        for entry in entries {
            if !entry.isDirectory { count += 1 }
            if let children = entry.children {
                count += countFiles(in: children)
            }
        }
        return count
    }
    
    private func countImages(in entries: [DiskCatalogEntry]) -> Int {
        var count = 0
        for entry in entries {
            if entry.isImage { count += 1 }
            if let children = entry.children {
                count += countImages(in: children)
            }
        }
        return count
    }
    
    private func flattenEntries(_ entries: [DiskCatalogEntry]) -> [DiskCatalogEntry] {
        var result: [DiskCatalogEntry] = []
        for entry in entries {
            result.append(entry)
            if let children = entry.children {
                result.append(contentsOf: flattenEntries(children))
            }
        }
        return result
    }
}
