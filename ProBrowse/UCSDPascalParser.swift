//
//  UCSDPascalParser.swift
//  ProBrowse
//
//  Parser for UCSD Pascal disk images (read-only)
//  Supports Apple II UCSD Pascal volumes
//

import Foundation

class UCSDPascalParser {
    
    // MARK: - Constants
    
    private static let BLOCK_SIZE = 512
    private static let DIRECTORY_BLOCK = 2
    private static let MAX_DIR_ENTRIES = 77
    private static let DIR_ENTRY_SIZE = 26
    
    // UCSD Pascal file types
    private static let fileTypes: [UInt8: String] = [
        0: "XDSK",    // Linked file (for large volumes)
        1: "CODE",    // Executable code
        2: "TEXT",    // Text file (with DLE compression)
        3: "INFO",    // Information file
        4: "DATA",    // Data file
        5: "GRAF",    // Graphics file
        6: "FOTO",    // Photo/screen image
        7: "SDIR"     // Secure directory
    ]
    
    // MARK: - Block Reading with Interleaving Support
    
    // DOS 3.3 sector interleave maps (same as DiskImageParser)
    private static let dosToProDOSMapTrack0: [Int] = [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
    private static let dosToProDOSMapData: [Int] = [0, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 15]
    
    /// Read a 512-byte block, handling interleaving for floppy images
    private static func readBlock(_ data: Data, blockIndex: Int, isDOSOrder: Bool) -> Data? {
        if !isDOSOrder {
            // Linear access
            let offset = blockIndex * BLOCK_SIZE
            guard offset + BLOCK_SIZE <= data.count else { return nil }
            return data.subdata(in: offset..<(offset + BLOCK_SIZE))
        } else {
            // DOS order interleaved
            let blocksPerTrack = 8
            let track = blockIndex / blocksPerTrack
            let blockInTrack = blockIndex % blocksPerTrack
            
            let sectorSize = 256
            let trackOffset = track * 16 * sectorSize
            
            guard trackOffset < data.count else { return nil }
            
            let mapping = (track == 0) ? dosToProDOSMapTrack0 : dosToProDOSMapData
            
            let lowerSectorIdx = mapping[blockInTrack * 2]
            let upperSectorIdx = mapping[blockInTrack * 2 + 1]
            
            let lowerOffset = trackOffset + (lowerSectorIdx * sectorSize)
            let upperOffset = trackOffset + (upperSectorIdx * sectorSize)
            
            guard lowerOffset + sectorSize <= data.count,
                  upperOffset + sectorSize <= data.count else { return nil }
            
            var blockData = Data()
            blockData.append(data.subdata(in: lowerOffset..<(lowerOffset + sectorSize)))
            blockData.append(data.subdata(in: upperOffset..<(upperOffset + sectorSize)))
            
            return blockData
        }
    }
    
    // MARK: - Volume Header Validation
    
    /// Check if this looks like a valid UCSD Pascal volume
    private static func isValidUCSDVolume(_ dirBlock: Data) -> Bool {
        guard dirBlock.count >= BLOCK_SIZE else { return false }
        
        // First entry in directory is the volume header
        // +$00-01: First block (should be 0)
        // +$02-03: Last block (next block after volume = total blocks)
        // +$04: File type (should be 0 for volume header)
        // +$05: Volume name length (1-7)
        // +$06-0C: Volume name (7 bytes)
        
        let firstBlock = UInt16(dirBlock[0]) | (UInt16(dirBlock[1]) << 8)
        let lastBlock = UInt16(dirBlock[2]) | (UInt16(dirBlock[3]) << 8)
        let fileType = dirBlock[4]
        let nameLength = dirBlock[5]
        
        // Volume header should have firstBlock = 0
        guard firstBlock == 0 else { return false }
        
        // Last block should be reasonable (6 to 65535)
        guard lastBlock >= 6 && lastBlock <= 65535 else { return false }
        
        // File type for volume header should be 0
        guard fileType == 0 else { return false }
        
        // Name length should be 1-7 for volume name
        guard nameLength >= 1 && nameLength <= 7 else { return false }
        
        // Check volume name is printable ASCII
        for i in 0..<Int(nameLength) {
            let char = dirBlock[6 + i]
            guard char >= 0x20 && char < 0x7F else { return false }
        }
        
        return true
    }
    
    // MARK: - Date Parsing
    
    /// Decode UCSD Pascal date format
    /// Format: bits 0-3 = month (1-12), bits 4-8 = day (1-31), bits 9-15 = year (0-99, relative to 1900)
    private static func decodeUCSDDate(_ dateBytes: [UInt8]) -> String? {
        guard dateBytes.count >= 2 else { return nil }
        
        let dateWord = UInt16(dateBytes[0]) | (UInt16(dateBytes[1]) << 8)
        
        // Check for zero date
        guard dateWord != 0 else { return nil }
        
        let month = Int(dateWord & 0x0F)
        let day = Int((dateWord >> 4) & 0x1F)
        let year = Int((dateWord >> 9) & 0x7F) + 1900
        
        // Validate
        guard month >= 1 && month <= 12 && day >= 1 && day <= 31 else { return nil }
        
        // Format date
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        
        guard let date = Calendar.current.date(from: components) else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        
        return formatter.string(from: date)
    }
    
    // MARK: - TEXT File Decompression
    
    /// Decompress UCSD Pascal TEXT file
    /// TEXT files use DLE (0x10) compression for runs of spaces
    /// and have a specific page structure
    private static func decompressTextFile(_ data: Data) -> Data {
        var result = Data()
        var i = 0
        
        while i < data.count {
            let byte = data[i]
            
            if byte == 0x10 {  // DLE - Data Link Escape
                // Next byte is count: actual spaces = count - 32
                i += 1
                if i < data.count {
                    let count = Int(data[i])
                    if count >= 32 {
                        let spaces = count - 32
                        result.append(contentsOf: [UInt8](repeating: 0x20, count: spaces))
                    }
                }
            } else if byte == 0x0D {  // CR - end of line
                result.append(0x0A)  // Convert to LF for macOS
            } else if byte == 0x00 {
                // NUL byte - could be page marker, skip
                // Page markers are NUL followed by page number bytes
                // For simplicity, we just skip NULs
            } else if byte >= 0x20 && byte < 0x7F {
                // Printable ASCII
                result.append(byte)
            } else if byte == 0x09 {
                // Tab
                result.append(byte)
            }
            // Skip other control characters
            
            i += 1
        }
        
        return result
    }
    
    // MARK: - Main Parser
    
    /// Parse a UCSD Pascal disk image
    static func parseUCSD(data: Data, diskName: String) throws -> DiskCatalog? {
        // Check minimum size (at least a few blocks)
        guard data.count >= BLOCK_SIZE * 6 else { return nil }
        
        // Determine if this is a floppy with DOS ordering
        let isFloppySize = data.count == 143360 || data.count == 819200
        var isDOSOrder = false
        var directoryBlock: Data?
        
        // Try linear first
        if let block = readBlock(data, blockIndex: DIRECTORY_BLOCK, isDOSOrder: false) {
            if isValidUCSDVolume(block) {
                isDOSOrder = false
                directoryBlock = block
                print("🔍 Detected UCSD Pascal (Linear order)")
            }
        }
        
        // If not found and it's floppy size, try DOS order
        if directoryBlock == nil && isFloppySize {
            if let block = readBlock(data, blockIndex: DIRECTORY_BLOCK, isDOSOrder: true) {
                if isValidUCSDVolume(block) {
                    isDOSOrder = true
                    directoryBlock = block
                    print("🔍 Detected UCSD Pascal (DOS order)")
                }
            }
        }
        
        guard let dirBlock = directoryBlock else {
            return nil
        }
        
        // Parse volume header (first entry)
        let volNameLength = Int(dirBlock[5])
        var volumeName = ""
        for i in 0..<min(volNameLength, 7) {
            let char = dirBlock[6 + i]
            if char >= 0x20 && char < 0x7F {
                volumeName.append(Character(UnicodeScalar(char)))
            }
        }
        
        let totalBlocks = Int(UInt16(dirBlock[2]) | (UInt16(dirBlock[3]) << 8))
        let numFiles = Int(UInt16(dirBlock[16]) | (UInt16(dirBlock[17]) << 8))
        
        print("📀 UCSD Pascal Volume: \(volumeName)")
        print("   Total blocks: \(totalBlocks)")
        print("   Files in directory: \(numFiles)")
        
        // Read directory entries
        // Directory spans blocks 2-5 (4 blocks = 2048 bytes = 78 entries of 26 bytes)
        var allDirData = Data()
        for blockNum in 2...5 {
            if let block = readBlock(data, blockIndex: blockNum, isDOSOrder: isDOSOrder) {
                allDirData.append(block)
            }
        }
        
        var entries: [DiskCatalogEntry] = []
        
        // Skip first entry (volume header), parse rest
        for entryIdx in 1..<MAX_DIR_ENTRIES {
            let entryOffset = entryIdx * DIR_ENTRY_SIZE
            guard entryOffset + DIR_ENTRY_SIZE <= allDirData.count else { break }
            
            let firstBlock = Int(UInt16(allDirData[entryOffset]) | (UInt16(allDirData[entryOffset + 1]) << 8))
            let lastBlock = Int(UInt16(allDirData[entryOffset + 2]) | (UInt16(allDirData[entryOffset + 3]) << 8))
            let fileType = allDirData[entryOffset + 4]
            let nameLength = Int(allDirData[entryOffset + 5])
            
            // Empty entry check
            if firstBlock == 0 && lastBlock == 0 { continue }
            if nameLength == 0 || nameLength > 15 { continue }
            
            // Validate block range
            if firstBlock >= lastBlock { continue }
            if lastBlock > totalBlocks { continue }
            
            // Parse filename
            var fileName = ""
            for i in 0..<nameLength {
                let char = allDirData[entryOffset + 6 + i]
                if char >= 0x20 && char < 0x7F {
                    fileName.append(Character(UnicodeScalar(char)))
                }
            }
            
            if fileName.isEmpty { continue }
            
            // Bytes used in last block
            let bytesInLastBlock = Int(UInt16(allDirData[entryOffset + 22]) | (UInt16(allDirData[entryOffset + 23]) << 8))
            
            // Calculate file size
            let numBlocks = lastBlock - firstBlock
            let fileSize = (numBlocks - 1) * BLOCK_SIZE + bytesInLastBlock
            
            // Parse modification date
            let dateBytes = [allDirData[entryOffset + 24], allDirData[entryOffset + 25]]
            let modDate = decodeUCSDDate(dateBytes)
            
            // Get file type string
            let fileTypeString = fileTypes[fileType] ?? String(format: "$%02X", fileType)
            
            // Extract file data
            var fileData = Data()
            for blockNum in firstBlock..<lastBlock {
                if let block = readBlock(data, blockIndex: blockNum, isDOSOrder: isDOSOrder) {
                    fileData.append(block)
                }
            }
            
            // Trim to actual size
            if fileData.count > fileSize {
                fileData = fileData.prefix(fileSize)
            }
            
            // For TEXT files, offer decompressed version
            let isTextFile = fileType == 2
            let processedData: Data
            if isTextFile {
                processedData = decompressTextFile(fileData)
            } else {
                processedData = fileData
            }
            
            print("   📄 \(fileName) (\(fileTypeString)) - \(fileSize) bytes, blocks \(firstBlock)-\(lastBlock)")
            
            entries.append(DiskCatalogEntry(
                name: fileName,
                fileType: fileType,
                fileTypeString: fileTypeString,
                auxType: UInt16(firstBlock),  // Store first block as auxType for reference
                size: fileSize,
                blocks: numBlocks,
                loadAddress: nil,
                length: processedData.count,
                data: processedData,
                isImage: fileType == 5 || fileType == 6,  // GRAF or FOTO
                isDirectory: false,
                children: nil,
                modificationDate: modDate,
                creationDate: nil
            ))
        }
        
        if entries.isEmpty {
            return nil
        }
        
        return DiskCatalog(
            diskName: volumeName.isEmpty ? diskName : volumeName,
            diskFormat: "UCSD Pascal",
            diskSize: data.count,
            entries: entries
        )
    }
}
