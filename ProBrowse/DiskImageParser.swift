//
//  DiskImageParser.swift
//  ProBrowse
//
//  Parser for ProDOS and DOS 3.3 disk images
//  Updated to handle .dsk (DOS Ordered) ProDOS images correctly.
//

import Foundation
import Combine

class DiskImageParser {
    
    // MARK: - DOS to ProDOS Mapping Constants
    
    // Track 0 (Directory): Uses countdown mapping for the Volume Directory
    // This "countdown" mapping: ProDOS logical sector N -> DOS physical sector (15-N)
    private static let dosToProDOSMapTrack0: [Int] = [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
    
    // Track 1+ (Data): Uses standard DOS 3.3 logical order for file data blocks
    // Based on DOS 3.3 Physical-to-Logical mapping from Apple II documentation:
    // Physical: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15
    // DOS Log:  0, 7,14, 6,13, 5,12, 4,11, 3,10, 2, 9, 1, 8,15
    //
    // Combined with ProDOS Block-to-Physical mapping:
    // Block 0: Phys 0+2  -> DOS Log 0+14
    // Block 1: Phys 4+6  -> DOS Log 13+12
    // Block 2: Phys 8+10 -> DOS Log 11+10
    // Block 3: Phys 12+14 -> DOS Log 9+8
    // Block 4: Phys 1+3  -> DOS Log 7+6
    // Block 5: Phys 5+7  -> DOS Log 5+4
    // Block 6: Phys 9+11 -> DOS Log 3+2
    // Block 7: Phys 13+15 -> DOS Log 1+15
    private static let dosToProDOSMapData: [Int] = [0, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 15]

    // MARK: - Date/Time Parsing
    
    private static func decodeProDOSDateTime(_ dateBytes: [UInt8], _ timeBytes: [UInt8]) -> String? {
        guard dateBytes.count >= 2 else { return nil }
        
        let dateWord = UInt16(dateBytes[0]) | (UInt16(dateBytes[1]) << 8)
        
        // Check if date is zero (unset)
        guard dateWord != 0 else { return nil }
        
        let year = Int((dateWord >> 9) & 0x7F) + 1900
        let month = Int((dateWord >> 5) & 0x0F)
        let day = Int(dateWord & 0x1F)
        
        // Validate date
        guard month >= 1, month <= 12, day >= 1, day <= 31 else {
            return nil
        }
        
        // Parse time (optional)
        var hour = 0
        var minute = 0
        if timeBytes.count >= 2 {
            let timeWord = UInt16(timeBytes[0]) | (UInt16(timeBytes[1]) << 8)
            hour = Int(timeWord & 0xFF)
            minute = Int((timeWord >> 8) & 0xFF)
            
            // Validate time (some disks have invalid time data)
            if hour >= 24 || minute >= 60 {
                hour = 0
                minute = 0
            }
        }
        
        // Create Date object
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        
        guard let date = Calendar.current.date(from: components) else {
            return nil
        }
        
        // Format using system locale
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        return formatter.string(from: date)
    }
    
    // MARK: - Block Reader Helper
    
    /// Validates if a block is a valid ProDOS Volume Directory Header
    private static func isValidProDOSVolumeHeader(_ block: Data) -> Bool {
        guard block.count >= 512 else { return false }
        
        // Check 1: Storage Type must be 0xF (Volume Directory Header)
        let storageType = (block[4] & 0xF0) >> 4
        guard storageType == 0x0F else { return false }
        
        // Check 2: Name Length must be 1-15
        let nameLength = Int(block[4] & 0x0F)
        guard nameLength >= 1 && nameLength <= 15 else { return false }
        
        // Check 3: Prev Block Pointer must be 0 (root has no previous)
        let prevBlock = UInt16(block[0]) | (UInt16(block[1]) << 8)
        guard prevBlock == 0 else { return false }
        
        // Check 4: Entry Length should be 39 (0x27)
        let entryLength = block[0x23]
        guard entryLength == 0x27 else { return false }
        
        // Check 5: Entries Per Block should be 13 (0x0D)
        let entriesPerBlock = block[0x24]
        guard entriesPerBlock == 0x0D else { return false }
        
        // Check 6: Volume Name must be printable ASCII (uppercase letters, digits, periods)
        var volumeName = ""
        for i in 0..<nameLength {
            let char = block[5 + i] & 0x7F
            // ProDOS allows: A-Z, 0-9, and period
            let isValid = (char >= 0x41 && char <= 0x5A) ||  // A-Z
                         (char >= 0x30 && char <= 0x39) ||  // 0-9
                         (char == 0x2E)                     // .
            guard isValid else { return false }
            volumeName.append(Character(UnicodeScalar(char)))
        }
        
        // Check 7: Volume name should not be empty after validation
        guard !volumeName.isEmpty else { return false }
        
        return true
    }
    
    /// Reads Block 2 specifically using Track 0 mapping (for format detection)
    private static func getBlock2Track0(from data: Data) -> Data? {
        let sectorSize = 256
        let track = 0
        let blockInTrack = 2
        let trackOffset = track * 16 * sectorSize
        
        guard trackOffset < data.count else { return nil }
        
        // Block 2 in Track 0 ALWAYS uses the Track 0 (Directory) mapping
        let mapping = dosToProDOSMapTrack0
        
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
    
    /// Reads a 512-byte block handling both Linear (.po) and Interleaved (.dsk) formats
    private static func getBlockData(from data: Data, blockIndex: Int, isDOSOrder: Bool) -> Data? {
        let blockSize = 512
        
        if !isDOSOrder {
            // Standard ProDOS Order (.po): Linear
            let offset = blockIndex * blockSize
            guard offset + blockSize <= data.count else { return nil }
            return data.subdata(in: offset..<(offset + blockSize))
        } else {
            // DOS Order (.dsk): Interleaved sectors
            // Calculate Track and "Block within Track"
            // 8 Blocks per track (because 1 Block = 2 Sectors, and there are 16 Sectors)
            let blocksPerTrack = 8
            let track = blockIndex / blocksPerTrack
            let blockInTrack = blockIndex % blocksPerTrack
            
            let sectorSize = 256
            let trackOffset = track * 16 * sectorSize
            
            guard trackOffset < data.count else { return nil }
            
            // Select the appropriate mapping based on track
            // Track 0: Directory uses countdown mapping
            // Track 1+: Data uses standard DOS 3.3 logical order
            let mapping = (track == 0) ? dosToProDOSMapTrack0 : dosToProDOSMapData
            
            // Find the two DOS sectors (Lower/Upper)
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
    
    // MARK: - Main Entry Point
    
    static func parseProDOS(data: Data, diskName: String) throws -> DiskCatalog? {
        let blockSize = 512
        guard data.count >= blockSize * 3 else { return nil }
        
        // --- Step 1: Detect Format Order ---
        var isDOSOrder = false
        var detected = false
        var rootBlockData: Data? = nil
        
        // Check standard ProDOS Order (Block 2 at linear offset 1024)
        if let block2PO = getBlockData(from: data, blockIndex: 2, isDOSOrder: false) {
            if isValidProDOSVolumeHeader(block2PO) {
                isDOSOrder = false
                detected = true
                rootBlockData = block2PO
                print("🔍 Detected Format: ProDOS Order (.po)")
            }
        }
        
        // Check DOS Order (Block 2 in Track 0 with Track 0 mapping)
        if !detected, let block2DSK = getBlock2Track0(from: data) {
            if isValidProDOSVolumeHeader(block2DSK) {
                isDOSOrder = true
                detected = true
                rootBlockData = block2DSK
                print("🔍 Detected Format: DOS Order (.dsk)")
            }
        }
        
        // Fallback based on extension if detection failed (Optional)
        if !detected {
            // ProDOS detection failed - return nil so DOS 3.3 parser can try
            print("⚠️ ProDOS detection failed - not a valid ProDOS volume")
            return nil
        }
        
        guard let rootBlock = rootBlockData else {
            print("❌ Could not find Root Directory Block")
            return nil
        }
        
        // --- Step 2: Parse Volume Header ---
        let nameLength = Int(rootBlock[4] & 0x0F)
        var volumeName = ""
        
        if nameLength > 0 && nameLength <= 15 {
            for i in 0..<nameLength {
                var char = rootBlock[5 + i] & 0x7F
                if char < 0x20 { char = char + 0x40 }
                volumeName.append(Character(UnicodeScalar(char)))
            }
        }
        
        // --- Step 3: Read Directory Tree ---
        let entries = readProDOSDirectory(data: data, startBlock: 2, isDOSOrder: isDOSOrder)
        
        return DiskCatalog(
            diskName: volumeName.isEmpty ? diskName : volumeName,
            diskFormat: isDOSOrder ? "ProDOS (DSK)" : "ProDOS (PO)",
            diskSize: data.count,
            entries: entries
        )
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
    
    private static func readProDOSDirectory(data: Data, startBlock: Int, isDOSOrder: Bool) -> [DiskCatalogEntry] {
        var entries: [DiskCatalogEntry] = []
        var currentBlock = startBlock
        var visitedBlocks = Set<Int>() // Safety against loops
        
        while currentBlock != 0 {
            if visitedBlocks.contains(currentBlock) { break }
            visitedBlocks.insert(currentBlock)
            
            print("📖 Reading directory block \(currentBlock)...")
            
            // USE helper to get data (de-interleaving if necessary)
            guard let blockData = getBlockData(from: data, blockIndex: currentBlock, isDOSOrder: isDOSOrder) else {
                print("❌ Failed to read block \(currentBlock)")
                break
            }
            
            // Standard Block 2 (Root) has header at +4 bytes. Subsequent blocks in chain don't have the 39 byte header skip logic usually,
            // BUT in ProDOS directory files, *every* block in the directory file contains entries.
            // Block structure:
            // Bytes 00-01: Pointer to previous block
            // Bytes 02-03: Pointer to next block
            // Entries start at byte 04.
            
            // However, the Volume Directory Header (only in the first block of root) occupies the first entry slot.
            // We usually skip it or parse it as volume info.
            
            // Is this the very first block of the directory?
            let entriesPerBlock = 13 // Standard is 13 entries per block (512 - 4) / 39 = 13.02
            
            var entriesInThisBlock = 0
            for entryIdx in 0..<entriesPerBlock {
                let entryOffset = 4 + (entryIdx * 39)
                
                // Safety check
                if entryOffset + 39 > blockData.count { continue }
                
                // Skip Volume Header Entry in the first block of the ROOT directory (Block 2)
                // The Volume Header is distinguishable by having a high nibble of 0xF in storage type (byte 0)
                // But wait, the loop reads offsets relative to blockData.
                // The Storage Type/Name Length byte is at offset 0 of the entry.
                
                let storageTypeByte = blockData[entryOffset]
                let storageType = (storageTypeByte & 0xF0) >> 4
                let nameLength = Int(storageTypeByte & 0x0F)
                
                // 0x00 = Deleted entry, 0xF = Volume Header (skip it for file list)
                if storageType == 0x00 { continue }
                if storageType == 0x0F { continue } // Skip Volume Header entry itself
                
                // Parse Name
                var fileName = ""
                if nameLength > 0 {
                    for i in 0..<nameLength {
                        var char = blockData[entryOffset + 1 + i] & 0x7F
                        if char < 0x20 { char += 0x40 }
                        fileName.append(Character(UnicodeScalar(char)))
                    }
                }
                
                let fileType = blockData[entryOffset + 16]
                let keyPointer = Int(blockData[entryOffset + 17]) | (Int(blockData[entryOffset + 18]) << 8)
                let blocksUsed = Int(blockData[entryOffset + 19]) | (Int(blockData[entryOffset + 20]) << 8)
                let eof = Int(blockData[entryOffset + 21]) | (Int(blockData[entryOffset + 22]) << 8) | (Int(blockData[entryOffset + 23]) << 16)
                let auxType = Int(blockData[entryOffset + 31]) | (Int(blockData[entryOffset + 32]) << 8)
                
                let creationDate = decodeProDOSDateTime([blockData[entryOffset + 24], blockData[entryOffset + 25]], [blockData[entryOffset + 26], blockData[entryOffset + 27]])
                let modificationDate = decodeProDOSDateTime([blockData[entryOffset + 33], blockData[entryOffset + 34]], [blockData[entryOffset + 35], blockData[entryOffset + 36]])
                
                if storageType == 0x0D {
                    // Subdirectory
                    let children = readProDOSDirectory(data: data, startBlock: keyPointer, isDOSOrder: isDOSOrder)
                    
                    entries.append(DiskCatalogEntry(
                        name: fileName,
                        fileType: 0x0F,
                        fileTypeString: "DIR",
                        auxType: 0,
                        size: blocksUsed * 512,
                        blocks: blocksUsed,
                        loadAddress: nil,
                        length: nil,
                        data: Data(),
                        isImage: false,
                        isDirectory: true,
                        children: children,
                        modificationDate: modificationDate,
                        creationDate: creationDate
                    ))
                } else {
                    // File
                    let fileData = extractProDOSFile(data: data, keyBlock: keyPointer, blocksUsed: blocksUsed, eof: eof, storageType: Int(storageType), isDOSOrder: isDOSOrder) ?? Data()
                    let isGraphicsFile = [0x08, 0xC0, 0xC1].contains(fileType)
                    
                    // Simple FileType mapping
                    let typeStr = String(format: "$%02X", fileType) // Fallback
                    // You can use your ProDOSFileTypeInfo helper here if available in your project
                    
                    entries.append(DiskCatalogEntry(
                        name: fileName,
                        fileType: fileType,
                        fileTypeString: typeStr,
                        auxType: UInt16(auxType),
                        size: eof,
                        blocks: blocksUsed,
                        loadAddress: auxType,
                        length: eof,
                        data: fileData,
                        isImage: isGraphicsFile,
                        isDirectory: false,
                        children: nil,
                        modificationDate: modificationDate,
                        creationDate: creationDate
                    ))
                    entriesInThisBlock += 1
                }
            }
            
            print("   Entries in block \(currentBlock): \(entriesInThisBlock)")
            
            // Get pointer to next block in directory chain
            let nextBlock = Int(blockData[2]) | (Int(blockData[3]) << 8)
            print("   Next block pointer: \(nextBlock)")
            print("   Found \(entries.count) total entries so far")
            currentBlock = nextBlock
        }
        
        print("✅ Directory reading complete: \(entries.count) entries")
        return entries
    }
    
    private static func extractProDOSFile(data: Data, keyBlock: Int, blocksUsed: Int, eof: Int, storageType: Int, isDOSOrder: Bool) -> Data? {
        var fileData = Data()
        
        if storageType == 1 {
            // Seedling file (single block)
            if let blockData = getBlockData(from: data, blockIndex: keyBlock, isDOSOrder: isDOSOrder) {
                fileData = blockData
            }
        }
        else if storageType == 2 {
            // Sapling file (index block with data blocks)
            if let indexBlock = getBlockData(from: data, blockIndex: keyBlock, isDOSOrder: isDOSOrder) {
                for i in 0..<256 {
                    let blockNumLo = Int(indexBlock[i])
                    let blockNumHi = Int(indexBlock[256 + i])
                    let blockNum = blockNumLo | (blockNumHi << 8)
                    
                    if blockNum == 0 {
                        // Sparse block (hole)
                        fileData.append(Data(repeating: 0, count: 512))
                    } else {
                        if let dataBlock = getBlockData(from: data, blockIndex: blockNum, isDOSOrder: isDOSOrder) {
                            fileData.append(dataBlock)
                        } else {
                            // Read error or out of bounds, fill with zeros to maintain offset
                            fileData.append(Data(repeating: 0, count: 512))
                        }
                    }
                }
            }
        }
        else if storageType == 3 {
            // Tree file (master index -> index blocks -> data blocks)
            if let masterIndex = getBlockData(from: data, blockIndex: keyBlock, isDOSOrder: isDOSOrder) {
                for i in 0..<256 {
                    let indexBlockNum = Int(masterIndex[i]) | (Int(masterIndex[256 + i]) << 8)
                    
                    // Note: ProDOS Tech Ref says Tree files are generally full up to EOF, but can be sparse.
                    // If Master Index entry is 0, it represents 256 * 512 bytes of zeros.
                    
                    if indexBlockNum == 0 {
                         // Huge sparse hole (128KB)
                         // We only append if we haven't passed EOF logic later, but for simplicity here:
                         // Ideally we shouldn't alloc 128KB ram if unnecessary, but let's be safe.
                         // Actually, strict parsing stops at EOF.
                         // Let's iterate standard logic.
                         let sparseChunk = Data(repeating: 0, count: 512 * 256)
                         fileData.append(sparseChunk)
                         continue
                    }
                    
                    if let indexBlock = getBlockData(from: data, blockIndex: indexBlockNum, isDOSOrder: isDOSOrder) {
                        for j in 0..<256 {
                            let dataBlockNum = Int(indexBlock[j]) | (Int(indexBlock[256 + j]) << 8)
                            
                            if dataBlockNum == 0 {
                                fileData.append(Data(repeating: 0, count: 512))
                            } else {
                                if let dataBlock = getBlockData(from: data, blockIndex: dataBlockNum, isDOSOrder: isDOSOrder) {
                                    fileData.append(dataBlock)
                                } else {
                                    fileData.append(Data(repeating: 0, count: 512))
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Trim to exact file size
        if fileData.count > eof {
            fileData = fileData.subdata(in: 0..<eof)
        }
        
        return fileData.isEmpty && eof > 0 ? nil : fileData
    }
    
    // MARK: - DOS 3.3 Catalog Reading (Standard)
    
    private static func readDOS33Catalog(data: Data, catalogTrack: Int, catalogSector: Int, sectorsPerTrack: Int, sectorSize: Int) -> [DiskCatalogEntry] {
        var entries: [DiskCatalogEntry] = []
        var currentTrack = catalogTrack
        var currentSector = catalogSector
        
        // DOS 3.3 stores sectors logically in .dsk usually, so simple offset calc works
        // unless it's a .nib file (which we aren't handling here).
        // Standard .dsk = DOS Order.
        
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
                    var char = data[entryOffset + 3 + i] & 0x7F
                    if char == 0 || char == 0x20 { break }
                    if char < 0x20 { char += 0x40 }
                    if char > 0 { fileName.append(Character(UnicodeScalar(char))) }
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
        
        for _ in 0..<1000 { // Limit T/S list traversal
            let tsListOffset = (currentTrack * sectorsPerTrack + currentSector) * sectorSize
            guard tsListOffset + sectorSize <= data.count else { break }
            
            for pairIdx in 0..<122 {
                let track = Int(data[tsListOffset + 12 + (pairIdx * 2)])
                let sector = Int(data[tsListOffset + 12 + (pairIdx * 2) + 1])
                
                if track == 0 { break } // End of sector list
                
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
