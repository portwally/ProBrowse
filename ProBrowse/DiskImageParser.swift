//
//  DiskImageParser.swift
//  ProBrowse
//
//  Parser for ProDOS and DOS 3.3 disk images
//

import Foundation
import Combine

class DiskImageParser {
    
    // MARK: - Main Entry Point
    
    static func parseProDOS(data: Data, diskName: String) throws -> DiskCatalog? {
        let blockSize = 512
        guard data.count >= blockSize * 3 else { return nil }
        
        // Try both block 2 (standard) and block 1 (some non-standard disks)
        for volumeDirBlock in [2, 1] {
            let volumeDirOffset = volumeDirBlock * blockSize
            guard volumeDirOffset + blockSize <= data.count else { continue }
            
            let storageType = (data[volumeDirOffset + 4] & 0xF0) >> 4
            guard storageType == 0x0F else { continue }
            
            let volumeNameLength = Int(data[volumeDirOffset + 4] & 0x0F)
            guard volumeNameLength > 0 && volumeNameLength <= 15 else { continue }
            
            var volumeName = ""
            for i in 0..<volumeNameLength {
                volumeName.append(Character(UnicodeScalar(data[volumeDirOffset + 5 + i])))
            }
            
            let entries = readProDOSDirectory(data: data, startBlock: volumeDirBlock, blockSize: blockSize)
            
            // Return catalog even if empty (valid ProDOS volume was found)
            return DiskCatalog(
                diskName: volumeName.isEmpty ? diskName : volumeName,
                diskFormat: "ProDOS",
                diskSize: data.count,
                entries: entries
            )
        }
        
        return nil
    }
    
    static func parseDOS33(data: Data, diskName: String) throws -> DiskCatalog? {
        let sectorsPerTrack = 16
        let sectorSize = 256
        
        guard data.count >= 35 * sectorsPerTrack * sectorSize else { return nil }
        
        // VTOC is at Track 17, Sector 0
        let vtocOffset = (17 * sectorsPerTrack + 0) * sectorSize
        guard vtocOffset + sectorSize <= data.count else { return nil }
        
        // Catalog starts at Track 17, Sector 15 (usually)
        let catalogTrack = Int(data[vtocOffset + 1])
        let catalogSector = Int(data[vtocOffset + 2])
        
        guard catalogTrack == 17 else { return nil }
        
        let entries = readDOS33Catalog(data: data, catalogTrack: catalogTrack, catalogSector: catalogSector, sectorsPerTrack: sectorsPerTrack, sectorSize: sectorSize)
        
        if entries.isEmpty { return nil }
        
        return DiskCatalog(
            diskName: diskName,
            diskFormat: "DOS 3.3",
            diskSize: data.count,
            entries: entries
        )
    }
    
    // MARK: - ProDOS Directory Reading
    
    private static func readProDOSDirectory(data: Data, startBlock: Int, blockSize: Int) -> [DiskCatalogEntry] {
        var entries: [DiskCatalogEntry] = []
        var currentBlock = startBlock
        
        for _ in 0..<100 {
            let blockOffset = currentBlock * blockSize
            guard blockOffset + blockSize <= data.count else { break }
            
            let entriesPerBlock = currentBlock == startBlock ? 12 : 13
            let entryStart = currentBlock == startBlock ? 4 + 39 : 4
            
            for entryIdx in 0..<entriesPerBlock {
                let entryOffset = blockOffset + entryStart + (entryIdx * 39)
                guard entryOffset + 39 <= data.count else { continue }
                
                let entryStorageType = (data[entryOffset] & 0xF0) >> 4
                if entryStorageType == 0 { continue }
                
                let nameLength = Int(data[entryOffset] & 0x0F)
                var fileName = ""
                for i in 0..<nameLength {
                    let char = data[entryOffset + 1 + i] & 0x7F  // Remove high bit
                    fileName.append(Character(UnicodeScalar(char)))
                }
                
                let fileType = data[entryOffset + 16]
                let keyPointer = Int(data[entryOffset + 17]) | (Int(data[entryOffset + 18]) << 8)
                let blocksUsed = Int(data[entryOffset + 19]) | (Int(data[entryOffset + 20]) << 8)
                let eof = Int(data[entryOffset + 21]) | (Int(data[entryOffset + 22]) << 8) | (Int(data[entryOffset + 23]) << 16)
                let auxType = Int(data[entryOffset + 31]) | (Int(data[entryOffset + 32]) << 8)
                
                // Handle directory
                if entryStorageType == 0x0D {
                    let children = readProDOSDirectory(data: data, startBlock: keyPointer, blockSize: blockSize)
                    
                    entries.append(DiskCatalogEntry(
                        name: fileName,
                        fileType: 0x0F,
                        fileTypeString: "DIR",
                        auxType: 0,
                        size: blocksUsed * blockSize,
                        blocks: blocksUsed,
                        loadAddress: nil,
                        length: nil,
                        data: Data(),
                        isImage: false,
                        isDirectory: true,
                        children: children
                    ))
                } else {
                    // Handle file
                    if let fileData = extractProDOSFile(data: data, keyBlock: keyPointer, blocksUsed: blocksUsed, eof: eof, storageType: Int(entryStorageType), blockSize: blockSize) {
                        
                        let isGraphicsFile = [0x08, 0xC0, 0xC1].contains(fileType)
                        
                        entries.append(DiskCatalogEntry(
                            name: fileName,
                            fileType: fileType,
                            fileTypeString: String(format: "$%02X", fileType),
                            auxType: UInt16(auxType),
                            size: eof,
                            blocks: blocksUsed,
                            loadAddress: auxType,
                            length: eof,
                            data: fileData,
                            isImage: isGraphicsFile,
                            isDirectory: false,
                            children: nil
                        ))
                    }
                }
            }
            
            // Next block pointer
            let nextBlock = Int(data[blockOffset + 2]) | (Int(data[blockOffset + 3]) << 8)
            if nextBlock == 0 { break }
            currentBlock = nextBlock
        }
        
        return entries
    }
    
    private static func extractProDOSFile(data: Data, keyBlock: Int, blocksUsed: Int, eof: Int, storageType: Int, blockSize: Int) -> Data? {
        var fileData = Data()
        
        if storageType == 1 {
            // Seedling file (single block)
            let offset = keyBlock * blockSize
            guard offset + blockSize <= data.count else { return nil }
            fileData = data.subdata(in: offset..<min(offset + eof, offset + blockSize, data.count))
        }
        else if storageType == 2 {
            // Sapling file (index block with data blocks)
            let indexOffset = keyBlock * blockSize
            guard indexOffset + blockSize <= data.count else { return nil }
            
            for i in 0..<256 {
                let blockNumLo = Int(data[indexOffset + i])
                let blockNumHi = Int(data[indexOffset + 256 + i])
                let blockNum = blockNumLo | (blockNumHi << 8)
                if blockNum == 0 { continue }  // Skip null entries (sparse file)
                
                let offset = blockNum * blockSize
                guard offset + blockSize <= data.count else { continue }
                fileData.append(data.subdata(in: offset..<(offset + blockSize)))
            }
            
            // Trim to exact file size
            if fileData.count > eof {
                fileData = fileData.subdata(in: 0..<eof)
            }
        }
        else if storageType == 3 {
            // Tree file (master index with index blocks)
            let masterIndexOffset = keyBlock * blockSize
            guard masterIndexOffset + blockSize <= data.count else { return nil }
            
            var totalBlocks = 0
            for i in 0..<256 {
                let indexBlockNumLo = Int(data[masterIndexOffset + i])
                let indexBlockNumHi = Int(data[masterIndexOffset + 256 + i])
                let indexBlockNum = indexBlockNumLo | (indexBlockNumHi << 8)
                if indexBlockNum == 0 { break }  // No more index blocks
                
                let indexOffset = indexBlockNum * blockSize
                guard indexOffset + blockSize <= data.count else { continue }
                
                var blocksInThisIndex = 0
                for j in 0..<256 {
                    let dataBlockNumLo = Int(data[indexOffset + j])
                    let dataBlockNumHi = Int(data[indexOffset + 256 + j])
                    let dataBlockNum = dataBlockNumLo | (dataBlockNumHi << 8)
                    if dataBlockNum == 0 { continue }  // Skip null entries (sparse file)
                    
                    let offset = dataBlockNum * blockSize
                    guard offset + blockSize <= data.count else { continue }
                    fileData.append(data.subdata(in: offset..<(offset + blockSize)))
                    blocksInThisIndex += 1
                }
                totalBlocks += blocksInThisIndex
                print("   [Parser] Index \(i) @ block#\(indexBlockNum): read \(blocksInThisIndex) blocks")
            }
            
            print("   [Parser] Total blocks read: \(totalBlocks), file size: \(fileData.count) / \(eof)")
            
            // Trim to exact file size
            if fileData.count > eof {
                fileData = fileData.subdata(in: 0..<eof)
            }
        }
        
        return fileData.isEmpty ? nil : fileData
    }
    
    // MARK: - DOS 3.3 Catalog Reading
    
    private static func readDOS33Catalog(data: Data, catalogTrack: Int, catalogSector: Int, sectorsPerTrack: Int, sectorSize: Int) -> [DiskCatalogEntry] {
        var entries: [DiskCatalogEntry] = []
        var currentTrack = catalogTrack
        var currentSector = catalogSector
        
        for _ in 0..<100 {
            let catalogOffset = (currentTrack * sectorsPerTrack + currentSector) * sectorSize
            guard catalogOffset + sectorSize <= data.count else { break }
            
            for entryIdx in 0..<7 {
                let entryOffset = catalogOffset + 11 + (entryIdx * 35)
                guard entryOffset + 35 <= data.count else { continue }
                
                let trackList = Int(data[entryOffset])
                let sectorList = Int(data[entryOffset + 1])
                
                if trackList == 0 || trackList == 0xFF { continue }
                
                var fileName = ""
                for i in 0..<30 {
                    let char = data[entryOffset + 3 + i] & 0x7F
                    if char == 0 || char == 0x20 { break }
                    if char > 0 {
                        fileName.append(Character(UnicodeScalar(char)))
                    }
                }
                fileName = fileName.trimmingCharacters(in: .whitespaces)
                
                if fileName.isEmpty { continue }
                
                let fileType = data[entryOffset + 2] & 0x7F
                let locked = (data[entryOffset + 2] & 0x80) != 0
                
                if let fileData = extractDOS33File(data: data, trackList: trackList, sectorList: sectorList, sectorsPerTrack: sectorsPerTrack, sectorSize: sectorSize) {
                    
                    let isGraphicsFile = (fileType == 0x04 || fileType == 0x42) && fileData.count > 8000
                    
                    entries.append(DiskCatalogEntry(
                        name: fileName + (locked ? " 🔒" : ""),
                        fileType: fileType,
                        fileTypeString: String(format: "$%02X", fileType),
                        auxType: 0,
                        size: fileData.count,
                        blocks: nil,
                        loadAddress: nil,
                        length: fileData.count,
                        data: fileData,
                        isImage: isGraphicsFile,
                        isDirectory: false,
                        children: nil
                    ))
                }
            }
            
            let nextTrack = Int(data[catalogOffset + 1])
            let nextSector = Int(data[catalogOffset + 2])
            
            if nextTrack == 0 { break }
            currentTrack = nextTrack
            currentSector = nextSector
        }
        
        return entries
    }
    
    private static func extractDOS33File(data: Data, trackList: Int, sectorList: Int, sectorsPerTrack: Int, sectorSize: Int) -> Data? {
        var fileData = Data()
        var currentTrack = trackList
        var currentSector = sectorList
        
        for _ in 0..<1000 {
            let tsListOffset = (currentTrack * sectorsPerTrack + currentSector) * sectorSize
            guard tsListOffset + sectorSize <= data.count else { break }
            
            for pairIdx in 0..<122 {
                let track = Int(data[tsListOffset + 12 + (pairIdx * 2)])
                let sector = Int(data[tsListOffset + 12 + (pairIdx * 2) + 1])
                
                if track == 0 { break }
                
                let dataOffset = (track * sectorsPerTrack + sector) * sectorSize
                guard dataOffset + sectorSize <= data.count else { continue }
                
                fileData.append(data.subdata(in: dataOffset..<(dataOffset + sectorSize)))
            }
            
            let nextTrack = Int(data[tsListOffset + 1])
            let nextSector = Int(data[tsListOffset + 2])
            
            if nextTrack == 0 { break }
            currentTrack = nextTrack
            currentSector = nextSector
        }
        
        return fileData.isEmpty ? nil : fileData
    }
}
