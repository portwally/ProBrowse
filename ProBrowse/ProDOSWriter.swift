//
//  ProDOSWriter.swift
//  ProBrowse
//
//  Direct ProDOS disk image manipulation without external tools
//  Updated with sector interleaving support for .dsk/.do floppy images
//

import Foundation

class ProDOSWriter {
    static let shared = ProDOSWriter()
    
    private let BLOCK_SIZE = 512
    private let VOLUME_DIR_BLOCK = 2
    private let ENTRIES_PER_BLOCK = 13  // 0x0D
    private let ENTRY_LENGTH = 39       // 0x27
    
    // MARK: - DOS to ProDOS Sector Interleaving Maps
    
    // Track 0 (Directory): Uses countdown mapping for the Volume Directory
    private let dosToProDOSMapTrack0: [Int] = [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
    
    // Track 1+ (Data): Uses standard DOS 3.3 logical order for file data blocks
    private let dosToProDOSMapData: [Int] = [0, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 15]
    
    private init() {}
    
    // MARK: - Floppy Image Detection
    
    /// Detects if disk image is a floppy that needs sector interleaving
    private func isDOSOrderFloppy(_ diskData: Data, diskImagePath: URL) -> Bool {
        let ext = diskImagePath.pathExtension.lowercased()
        let isFloppySize = diskData.count == 143360 || diskData.count == 819200
        let isFloppyExtension = (ext == "dsk" || ext == "do")
        
        // Only .dsk and .do files need interleaving (and only if floppy size)
        return isFloppySize && isFloppyExtension
    }
    
    // MARK: - Block Read/Write with Interleaving Support
    
    /// Reads a 512-byte block from disk data, handling sector interleaving for floppy images
    private func readBlock(_ diskData: Data, blockIndex: Int, dataOffset: Int, isDOSOrder: Bool) -> Data? {
        if !isDOSOrder {
            // Standard ProDOS Order (.po, .hdv, .2mg): Linear access
            let offset = dataOffset + (blockIndex * BLOCK_SIZE)
            guard offset + BLOCK_SIZE <= diskData.count else { return nil }
            return diskData.subdata(in: offset..<(offset + BLOCK_SIZE))
        } else {
            // DOS Order (.dsk, .do): Interleaved sectors
            let blocksPerTrack = 8
            let track = blockIndex / blocksPerTrack
            let blockInTrack = blockIndex % blocksPerTrack
            
            let sectorSize = 256
            let trackOffset = dataOffset + (track * 16 * sectorSize)
            
            guard trackOffset < diskData.count else { return nil }
            
            // Select mapping based on track
            let mapping = (track == 0) ? dosToProDOSMapTrack0 : dosToProDOSMapData
            
            // Get the two sector indices for this block
            let lowerSectorIdx = mapping[blockInTrack * 2]
            let upperSectorIdx = mapping[blockInTrack * 2 + 1]
            
            let lowerOffset = trackOffset + (lowerSectorIdx * sectorSize)
            let upperOffset = trackOffset + (upperSectorIdx * sectorSize)
            
            guard lowerOffset + sectorSize <= diskData.count,
                  upperOffset + sectorSize <= diskData.count else { return nil }
            
            var blockData = Data()
            blockData.append(diskData.subdata(in: lowerOffset..<(lowerOffset + sectorSize)))
            blockData.append(diskData.subdata(in: upperOffset..<(upperOffset + sectorSize)))
            
            return blockData
        }
    }
    
    /// Writes a 512-byte block to disk data, handling sector interleaving for floppy images
    private func writeBlock(_ diskData: NSMutableData, blockIndex: Int, blockData: Data, dataOffset: Int, isDOSOrder: Bool) {
        guard blockData.count == BLOCK_SIZE else {
            print("   ❌ Block data size mismatch: \(blockData.count) != \(BLOCK_SIZE)")
            return
        }
        
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        
        if !isDOSOrder {
            // Standard ProDOS Order (.po, .hdv, .2mg): Linear access
            let offset = dataOffset + (blockIndex * BLOCK_SIZE)
            blockData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                memcpy(bytes + offset, ptr.baseAddress!, BLOCK_SIZE)
            }
        } else {
            // DOS Order (.dsk, .do): Interleaved sectors
            let blocksPerTrack = 8
            let track = blockIndex / blocksPerTrack
            let blockInTrack = blockIndex % blocksPerTrack
            
            let sectorSize = 256
            let trackOffset = dataOffset + (track * 16 * sectorSize)
            
            // Select mapping based on track
            let mapping = (track == 0) ? dosToProDOSMapTrack0 : dosToProDOSMapData
            
            // Get the two sector indices for this block
            let lowerSectorIdx = mapping[blockInTrack * 2]
            let upperSectorIdx = mapping[blockInTrack * 2 + 1]
            
            let lowerOffset = trackOffset + (lowerSectorIdx * sectorSize)
            let upperOffset = trackOffset + (upperSectorIdx * sectorSize)
            
            // Write lower 256 bytes to first sector
            blockData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                memcpy(bytes + lowerOffset, ptr.baseAddress!, sectorSize)
                memcpy(bytes + upperOffset, ptr.baseAddress! + sectorSize, sectorSize)
            }
        }
    }
    
    // MARK: - 2MG Header Detection
    
    /// Detects if disk image has 2MG header and returns data offset
    private func get2MGDataOffset(_ diskData: Data) -> Int {
        // Check for 2IMG/2MG signature
        if diskData.count >= 64 {
            let signature = diskData[0..<4]
            // "2IMG" signature
            if signature == Data([0x32, 0x49, 0x4D, 0x47]) {
                // 2MG files have 64-byte header
                return 64
            }
        }
        return 0  // No header, data starts at offset 0
    }
    
    // MARK: - Sanitize Filename
    
    /// Sanitizes a filename for ProDOS: removes invalid chars, max 15 chars, uppercase
    private func sanitizeProDOSFilename(_ filename: String) -> String {
        var name = filename.uppercased()
        
        // ProDOS allows: A-Z, 0-9, and period (.)
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "."))
        name = name.filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return validChars.contains(scalar)
        }
        
        // Max 15 characters
        if name.count > 15 {
            name = String(name.prefix(15))
        }
        
        // ProDOS requirement: First character must be a letter
        if let firstChar = name.first, !firstChar.isLetter {
            name = "A" + name  // Prepend 'A' if starts with number or period
            if name.count > 15 {
                name = String(name.prefix(15))
            }
        }
        
        // Ensure not empty
        if name.isEmpty {
            name = "UNNAMED"
        }
        
        return name
    }
    
    // MARK: - Add File to Disk Image
    
    /// Adds a file to a ProDOS disk image
    /// - Parameters:
    ///   - parentPath: Path to parent directory (e.g., "/" for root, "/SYSTEM" for subdirectory)
    func addFile(diskImagePath: URL, fileName: String, fileData: Data, fileType: UInt8, auxType: UInt16, parentPath: String = "/", completion: @escaping (Bool, String) -> Void) {
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Sanitize filename for ProDOS (remove invalid chars, max 15 chars)
                let sanitizedName = self.sanitizeProDOSFilename(fileName)
                
                // Load entire disk image into NSMutableData for safe byte manipulation
                guard let diskData = NSMutableData(contentsOf: diskImagePath) else {
                    DispatchQueue.main.async {
                        completion(false, "Could not read disk image")
                    }
                    return
                }
                
                let dataOffset = self.get2MGDataOffset(Data(referencing: diskData))
                let isDOSOrder = self.isDOSOrderFloppy(Data(referencing: diskData), diskImagePath: diskImagePath)
                
                if isDOSOrder {
                    print("   📀 DOS Order floppy detected - using sector interleaving")
                }
                
                // Check if filename already exists and rename if needed
                var finalName = sanitizedName
                var counter = 1
                while self.fileExists(diskData, fileName: finalName, dataOffset: dataOffset, isDOSOrder: isDOSOrder) {
                    // Auto-rename: FILENAME -> FILENAME.1, FILENAME.2, etc
                    let baseName = String(sanitizedName.prefix(13)) // Leave room for ".XX"
                    finalName = "\(baseName).\(counter)"
                    counter += 1
                    
                    if counter > 99 {
                        DispatchQueue.main.async {
                            completion(false, "Too many files with same name")
                        }
                        return
                    }
                }
                
                if finalName != sanitizedName {
                    print("   ⚠️ File exists - renamed to: \(finalName)")
                }
                
                print("📝 Adding file to ProDOS image:")
                print("   Original: \(fileName)")
                print("   Sanitized: \(sanitizedName)")
                print("   Final name: \(finalName)")
                print("   Parent path: \(parentPath)")
                print("   Size: \(fileData.count) bytes")
                print("   Type: $\(String(format: "%02X", fileType))")
                print("   Image: \(diskImagePath.lastPathComponent)")
                print("   DOS Order: \(isDOSOrder)")
                
                // Find target directory block
                guard let targetDirBlock = self.findDirectoryBlock(diskData, path: parentPath, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                    DispatchQueue.main.async {
                        completion(false, "Parent directory not found: \(parentPath)")
                    }
                    return
                }
                
                print("   📂 Target directory block: \(targetDirBlock)")
                
                // 1. Find free directory entry in target directory
                guard let (dirBlock, entryOffsetInBlock) = self.findFreeDirectoryEntry(diskData, dirBlock: targetDirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                    DispatchQueue.main.async {
                        completion(false, "No free directory entries in \(parentPath)")
                    }
                    return
                }
                
                print("   📂 Free entry at block \(dirBlock), entry offset \(entryOffsetInBlock)")
                
                // 2. Allocate blocks for file data
                let blocksNeeded = max(1, (fileData.count + self.BLOCK_SIZE - 1) / self.BLOCK_SIZE)
                guard let dataBlocks = self.allocateBlocks(diskData, count: blocksNeeded, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                    DispatchQueue.main.async {
                        completion(false, "Not enough free blocks (need \(blocksNeeded))")
                    }
                    return
                }
                
                print("   💾 Allocated \(blocksNeeded) blocks: \(dataBlocks)")
                
                // 3. Write file data to allocated blocks
                self.writeFileData(diskData, fileData: fileData, blocks: dataBlocks, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                
                // 4. For sapling/tree files, create index block(s)
                var keyBlock = 0  // Will be set based on file type
                var totalBlocks = dataBlocks.count
                
                if dataBlocks.isEmpty {
                    // Zero-length file - no blocks needed
                    keyBlock = 0
                    totalBlocks = 0
                    print("   📄 Zero-length file (no blocks)")
                    
                } else if dataBlocks.count > 256 {
                    // Tree file - need master index + multiple index blocks
                    let numIndexBlocks = (dataBlocks.count + 255) / 256  // Round up
                    
                    guard let indexBlocks = self.allocateBlocks(diskData, count: numIndexBlocks, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                        DispatchQueue.main.async {
                            completion(false, "Could not allocate index blocks")
                        }
                        return
                    }
                    
                    guard let masterIndexBlocks = self.allocateBlocks(diskData, count: 1, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                        DispatchQueue.main.async {
                            completion(false, "Could not allocate master index block")
                        }
                        return
                    }
                    
                    keyBlock = masterIndexBlocks[0]
                    totalBlocks += numIndexBlocks + 1  // Include all index blocks + master
                    
                    // Create index blocks
                    for i in 0..<numIndexBlocks {
                        let startIdx = i * 256
                        let endIdx = min(startIdx + 256, dataBlocks.count)
                        let blocksForThisIndex = Array(dataBlocks[startIdx..<endIdx])
                        self.createIndexBlock(diskData, indexBlock: indexBlocks[i], dataBlocks: blocksForThisIndex, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                    }
                    
                    // Create master index block pointing to index blocks
                    self.createMasterIndexBlock(diskData, masterIndexBlock: keyBlock, indexBlocks: indexBlocks, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                    print("   🌳 Created tree file: master index at \(keyBlock), \(numIndexBlocks) index blocks")
                    
                } else if dataBlocks.count > 1 {
                    // Sapling file - need one index block
                    guard let indexBlocks = self.allocateBlocks(diskData, count: 1, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                        DispatchQueue.main.async {
                            completion(false, "Could not allocate index block")
                        }
                        return
                    }
                    keyBlock = indexBlocks[0]
                    totalBlocks += 1  // Include index block in count
                    self.createIndexBlock(diskData, indexBlock: keyBlock, dataBlocks: dataBlocks, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                    print("   📇 Created index block at \(keyBlock)")
                    
                } else {
                    // Seedling file (1 block only)
                    keyBlock = dataBlocks[0]
                }
                
                // 5. Create directory entry
                self.createDirectoryEntry(diskData, dirBlock: dirBlock, entryOffsetInBlock: entryOffsetInBlock,
                                        fileName: finalName, fileType: fileType, auxType: auxType,
                                        keyBlock: keyBlock, blockCount: totalBlocks, fileSize: fileData.count,
                                        dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                
                // 6. Update file count in target directory
                self.incrementFileCount(diskData, dirBlock: targetDirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                
                // 7. Write modified disk image back to file
                try diskData.write(to: diskImagePath, options: .atomic)
                
                print("   ✅ File added successfully!")
                
                DispatchQueue.main.async {
                    completion(true, "File added successfully")
                }
                
            } catch {
                print("   ❌ Error: \(error)")
                DispatchQueue.main.async {
                    completion(false, "Error writing disk: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Create Index Block
    
    /// Creates a master index block for tree files (storage type 3)
    private func createMasterIndexBlock(_ diskData: NSMutableData, masterIndexBlock: Int, indexBlocks: [Int], dataOffset: Int, isDOSOrder: Bool) {
        var blockData = Data(repeating: 0, count: BLOCK_SIZE)
        
        // Write index block pointers
        // Format: first 256 bytes are low bytes, second 256 bytes are high bytes
        for i in 0..<min(indexBlocks.count, 256) {
            let block = indexBlocks[i]
            blockData[i] = UInt8(block & 0xFF)
            blockData[256 + i] = UInt8((block >> 8) & 0xFF)
        }
        
        writeBlock(diskData, blockIndex: masterIndexBlock, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
    }
    
    /// Creates an index block for sapling files (storage type 2)
    private func createIndexBlock(_ diskData: NSMutableData, indexBlock: Int, dataBlocks: [Int], dataOffset: Int, isDOSOrder: Bool) {
        var blockData = Data(repeating: 0, count: BLOCK_SIZE)
        
        // Write data block pointers
        // Format: first 256 bytes are low bytes, second 256 bytes are high bytes
        for i in 0..<min(dataBlocks.count, 256) {
            let block = dataBlocks[i]
            blockData[i] = UInt8(block & 0xFF)
            blockData[256 + i] = UInt8((block >> 8) & 0xFF)
        }
        
        writeBlock(diskData, blockIndex: indexBlock, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
    }
    
    // MARK: - Find Directory Block by Path
    
    /// Finds the directory block for a given path
    private func findDirectoryBlock(_ diskData: NSMutableData, path: String, dataOffset: Int, isDOSOrder: Bool) -> Int? {
        // Root directory
        if path == "/" {
            return VOLUME_DIR_BLOCK
        }
        
        // Parse path components (e.g., "/SYSTEM/FSTS" -> ["SYSTEM", "FSTS"])
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return VOLUME_DIR_BLOCK }
        
        var currentDirBlock = VOLUME_DIR_BLOCK
        
        // Navigate through each path component
        for dirName in components {
            guard let (_, entryData) = findFileEntryInDirectory(diskData, dirBlock: currentDirBlock, fileName: dirName, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                print("   ❌ Directory '\(dirName)' not found in path")
                return nil
            }
            
            // Check if it's actually a directory
            let storageType = entryData[0] >> 4
            guard storageType == 0xD else {
                print("   ❌ '\(dirName)' is not a directory (storage type: \(storageType))")
                return nil
            }
            
            // Get the subdirectory's block
            let keyBlockLo = entryData[0x11]
            let keyBlockHi = entryData[0x12]
            currentDirBlock = Int(keyBlockLo) | (Int(keyBlockHi) << 8)
        }
        
        return currentDirBlock
    }
    
    /// Finds a file entry within a specific directory block - returns (blockNum, entryData)
    private func findFileEntryInDirectory(_ diskData: NSMutableData, dirBlock: Int, fileName: String, dataOffset: Int, isDOSOrder: Bool) -> (block: Int, entryData: Data)? {
        var currentBlock = dirBlock
        var entryIndex = 1  // Skip header entry
        
        while currentBlock != 0 {
            guard let blockData = readBlock(Data(referencing: diskData), blockIndex: currentBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                break
            }
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = blockData[entryOffset] >> 4
                
                if storageType != 0 {
                    // Read entry name
                    let nameLength = Int(blockData[entryOffset] & 0x0F)
                    var entryName = ""
                    for i in 0..<min(nameLength, 15) {
                        let char = blockData[entryOffset + 1 + i] & 0x7F
                        entryName.append(Character(UnicodeScalar(char)))
                    }
                    
                    if entryName.uppercased() == fileName.uppercased() {
                        let entryData = blockData.subdata(in: entryOffset..<(entryOffset + ENTRY_LENGTH))
                        return (currentBlock, entryData)
                    }
                }
                
                entryIndex += 1
            }
            
            // Move to next block in directory chain
            let nextBlockLo = Int(blockData[2])
            let nextBlockHi = Int(blockData[3])
            currentBlock = nextBlockLo | (nextBlockHi << 8)
            entryIndex = 0
        }
        
        return nil
    }
    
    // MARK: - Find Free Directory Entry
    
    private func findFreeDirectoryEntry(_ diskData: NSMutableData, dirBlock: Int, dataOffset: Int, isDOSOrder: Bool) -> (block: Int, entryOffsetInBlock: Int)? {
        var currentBlock = dirBlock
        var entryIndex = 1  // Skip header entry
        
        while currentBlock != 0 {
            guard let blockData = readBlock(Data(referencing: diskData), blockIndex: currentBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                break
            }
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = blockData[entryOffset] >> 4
                
                if storageType == 0 {
                    // Found free entry - return block number and offset within block
                    return (currentBlock, entryOffset)
                }
                
                entryIndex += 1
            }
            
            let nextBlockLo = Int(blockData[2])
            let nextBlockHi = Int(blockData[3])
            currentBlock = nextBlockLo | (nextBlockHi << 8)
            entryIndex = 0
        }
        
        return nil
    }
    
    // MARK: - Allocate Blocks
    
    private func allocateBlocks(_ diskData: NSMutableData, count: Int, dataOffset: Int, isDOSOrder: Bool) -> [Int]? {
        guard count > 0 else { return [] }
        
        var allocatedBlocks: [Int] = []
        
        // Read volume header to get total blocks
        guard let volBlock = readBlock(Data(referencing: diskData), blockIndex: VOLUME_DIR_BLOCK, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
            return nil
        }
        
        let totalBlocksLo = Int(volBlock[0x29])
        let totalBlocksHi = Int(volBlock[0x2A])
        let totalBlocks = totalBlocksLo | (totalBlocksHi << 8)
        
        let startBlock = 24  // Start searching after system blocks
        
        print("   🔍 Searching for \(count) free blocks (total: \(totalBlocks))")
        
        // Safety check
        if totalBlocks <= startBlock {
            print("   ❌ Error: totalBlocks (\(totalBlocks)) <= startBlock (\(startBlock))")
            return nil
        }
        
        let bitmapStartBlock = 6
        
        for block in startBlock..<totalBlocks {
            if allocatedBlocks.count >= count {
                break
            }
            
            let bitIndex = block
            let byteIndex = bitIndex / 8
            let bitPosition = 7 - (bitIndex % 8)
            
            // Calculate which bitmap block and byte offset
            let bitmapBlock = bitmapStartBlock + (byteIndex / BLOCK_SIZE)
            let bitmapByteOffset = byteIndex % BLOCK_SIZE
            
            // Read bitmap block
            guard let bitmapBlockData = readBlock(Data(referencing: diskData), blockIndex: bitmapBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                continue
            }
            
            let bitmapByte = bitmapBlockData[bitmapByteOffset]
            let isFree = (bitmapByte & (1 << bitPosition)) != 0
            
            if isFree {
                allocatedBlocks.append(block)
                
                // Mark as allocated by writing back the bitmap block
                var mutableBitmapBlock = bitmapBlockData
                mutableBitmapBlock[bitmapByteOffset] = bitmapByte & ~(1 << bitPosition)
                writeBlock(diskData, blockIndex: bitmapBlock, blockData: mutableBitmapBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
            }
        }
        
        if allocatedBlocks.count < count {
            return nil
        }
        
        return allocatedBlocks
    }
    
    // MARK: - Write File Data
    
    private func writeFileData(_ diskData: NSMutableData, fileData: Data, blocks: [Int], dataOffset: Int, isDOSOrder: Bool) {
        print("   📝 Writing \(fileData.count) bytes to \(blocks.count) blocks")
        
        var dataPosition = 0
        
        for (index, block) in blocks.enumerated() {
            let bytesToWrite = min(BLOCK_SIZE, fileData.count - dataPosition)
            
            var blockData = Data(repeating: 0, count: BLOCK_SIZE)
            if bytesToWrite > 0 {
                blockData.replaceSubrange(0..<bytesToWrite, with: fileData.subdata(in: dataPosition..<(dataPosition + bytesToWrite)))
            }
            
            print("   📦 Block \(index): block#\(block), writing \(bytesToWrite) bytes")
            
            writeBlock(diskData, blockIndex: block, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
            
            dataPosition += bytesToWrite
        }
        
        print("   ✅ Wrote \(dataPosition) bytes total")
    }
    
    // MARK: - Create Directory Entry
    
    private func createDirectoryEntry(_ diskData: NSMutableData, dirBlock: Int, entryOffsetInBlock: Int,
                                     fileName: String, fileType: UInt8, auxType: UInt16,
                                     keyBlock: Int, blockCount: Int, fileSize: Int,
                                     dataOffset: Int, isDOSOrder: Bool) {
        
        // Read current directory block
        guard var blockData = readBlock(Data(referencing: diskData), blockIndex: dirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
            return
        }
        
        let storageType: UInt8
        if blockCount == 0 {
            storageType = 1  // Seedling for zero-length file
        } else if blockCount == 1 {
            storageType = 1  // Seedling
        } else if blockCount <= 256 {
            storageType = 2  // Sapling (has index block)
        } else {
            storageType = 3  // Tree (has master index)
        }
        
        var nameBytes = [UInt8](repeating: 0x00, count: 15)
        let nameData = fileName.uppercased().data(using: .ascii) ?? Data()
        let nameLen = min(nameData.count, 15)
        for i in 0..<nameLen {
            nameBytes[i] = nameData[i]
        }
        
        print("   📝 Filename bytes: \(nameBytes.prefix(nameLen).map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        var entry = [UInt8](repeating: 0, count: ENTRY_LENGTH)
        
        entry[0] = (storageType << 4) | UInt8(nameLen)
        
        for i in 0..<15 {
            entry[1 + i] = nameBytes[i]
        }
        
        entry[0x10] = fileType
        
        entry[0x11] = UInt8(keyBlock & 0xFF)
        entry[0x12] = UInt8((keyBlock >> 8) & 0xFF)
        
        entry[0x13] = UInt8(blockCount & 0xFF)
        entry[0x14] = UInt8((blockCount >> 8) & 0xFF)
        
        entry[0x15] = UInt8(fileSize & 0xFF)
        entry[0x16] = UInt8((fileSize >> 8) & 0xFF)
        entry[0x17] = UInt8((fileSize >> 16) & 0xFF)
        
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        
        let year = (components.year ?? 2024) - 1900
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let dateWord = (year << 9) | (month << 5) | day
        entry[0x18] = UInt8(dateWord & 0xFF)
        entry[0x19] = UInt8((dateWord >> 8) & 0xFF)
        entry[0x1A] = UInt8(hour & 0x1F)
        entry[0x1B] = UInt8(minute & 0x3F)
        
        entry[0x1C] = 0x00
        entry[0x1D] = 0x00
        entry[0x1E] = 0xE3
        
        entry[0x1F] = UInt8(auxType & 0xFF)
        entry[0x20] = UInt8((auxType >> 8) & 0xFF)
        
        entry[0x21] = entry[0x18]
        entry[0x22] = entry[0x19]
        entry[0x23] = entry[0x1A]
        entry[0x24] = entry[0x1B]
        
        entry[0x25] = 0x00
        entry[0x26] = 0x00
        
        // Write entry into block data
        for i in 0..<ENTRY_LENGTH {
            blockData[entryOffsetInBlock + i] = entry[i]
        }
        
        // Write block back to disk
        writeBlock(diskData, blockIndex: dirBlock, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
    }
    
    // MARK: - Increment File Count
    
    private func incrementFileCount(_ diskData: NSMutableData, dirBlock: Int, dataOffset: Int, isDOSOrder: Bool) {
        guard var blockData = readBlock(Data(referencing: diskData), blockIndex: dirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
            return
        }
        
        // File count at +$25-$26 (same for volume dir and subdirs)
        let fileCountOffset = 0x25
        
        let currentCountLo = Int(blockData[fileCountOffset])
        let currentCountHi = Int(blockData[fileCountOffset + 1])
        var fileCount = currentCountLo | (currentCountHi << 8)
        
        fileCount += 1
        
        blockData[fileCountOffset] = UInt8(fileCount & 0xFF)
        blockData[fileCountOffset + 1] = UInt8((fileCount >> 8) & 0xFF)
        
        writeBlock(diskData, blockIndex: dirBlock, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
        
        print("   📊 Updated file count in block \(dirBlock): \(fileCount)")
    }
    
    // MARK: - Check File Exists
    
    private func fileExists(_ diskData: NSMutableData, fileName: String, dataOffset: Int, isDOSOrder: Bool) -> Bool {
        return findFileEntry(Data(referencing: diskData), fileName: fileName, dataOffset: dataOffset, isDOSOrder: isDOSOrder) != nil
    }
    
    // MARK: - Find File Entry
    
    private func findFileEntry(_ diskData: Data, fileName: String, dataOffset: Int, isDOSOrder: Bool, dirBlock: Int? = nil) -> (block: Int, entryOffsetInBlock: Int)? {
        let searchName = fileName.uppercased()
        
        print("🔍 Searching for file: '\(searchName)' (dataOffset: \(dataOffset), isDOSOrder: \(isDOSOrder))")
        
        if let specificDir = dirBlock {
            return searchDirectoryOnly(diskData, directoryBlock: specificDir, fileName: searchName, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
        } else {
            return searchDirectory(diskData, directoryBlock: VOLUME_DIR_BLOCK, fileName: searchName, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
        }
    }
    
    /// Searches ONLY in the specified directory (non-recursive)
    private func searchDirectoryOnly(_ diskData: Data, directoryBlock: Int, fileName: String, dataOffset: Int, isDOSOrder: Bool) -> (block: Int, entryOffsetInBlock: Int)? {
        var currentBlock = directoryBlock
        var entryIndex = (directoryBlock == VOLUME_DIR_BLOCK) ? 1 : 0
        
        while currentBlock != 0 {
            guard let blockData = readBlock(diskData, blockIndex: currentBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                break
            }
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = blockData[entryOffset] >> 4
                
                if storageType != 0 {
                    let nameLen = Int(blockData[entryOffset] & 0x0F)
                    var entryName = ""
                    for i in 0..<nameLen {
                        let char = blockData[entryOffset + 1 + i] & 0x7F
                        entryName.append(Character(UnicodeScalar(char)))
                    }
                    
                    if entryName == fileName {
                        return (currentBlock, entryOffset)
                    }
                }
                
                entryIndex += 1
            }
            
            let nextBlockLo = blockData[2]
            let nextBlockHi = blockData[3]
            currentBlock = Int(nextBlockLo) | (Int(nextBlockHi) << 8)
            entryIndex = 0
        }
        
        return nil
    }
    
    private func searchDirectory(_ diskData: Data, directoryBlock: Int, fileName: String, dataOffset: Int, isDOSOrder: Bool) -> (block: Int, entryOffsetInBlock: Int)? {
        var currentBlock = directoryBlock
        var entryIndex = (directoryBlock == VOLUME_DIR_BLOCK) ? 1 : 0
        var subdirectories: [(block: Int, name: String)] = []
        
        print("   📂 Searching directory block \(directoryBlock)")
        
        while currentBlock != 0 {
            guard let blockData = readBlock(diskData, blockIndex: currentBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                print("   ❌ Failed to read block \(currentBlock)")
                break
            }
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = blockData[entryOffset] >> 4
                
                if storageType != 0 {
                    let nameLen = Int(blockData[entryOffset] & 0x0F)
                    var entryName = ""
                    for i in 0..<nameLen {
                        let char = blockData[entryOffset + 1 + i] & 0x7F
                        entryName.append(Character(UnicodeScalar(char)))
                    }
                    
                    print("      Found: '\(entryName)' (storage type: \(storageType))")
                    
                    if entryName == fileName {
                        print("      ✅ Match found!")
                        return (currentBlock, entryOffset)
                    }
                    
                    // If directory, remember for recursive search
                    if storageType == 0xD {
                        let keyBlockLo = blockData[entryOffset + 0x11]
                        let keyBlockHi = blockData[entryOffset + 0x12]
                        let keyBlock = Int(keyBlockLo) | (Int(keyBlockHi) << 8)
                        subdirectories.append((block: keyBlock, name: entryName))
                    }
                }
                
                entryIndex += 1
            }
            
            let nextBlockLo = blockData[2]
            let nextBlockHi = blockData[3]
            currentBlock = Int(nextBlockLo) | (Int(nextBlockHi) << 8)
            entryIndex = 0
        }
        
        // Search subdirectories recursively
        for subdir in subdirectories {
            if let result = searchDirectory(diskData, directoryBlock: subdir.block, fileName: fileName, dataOffset: dataOffset, isDOSOrder: isDOSOrder) {
                return result
            }
        }
        
        return nil
    }
    
    // MARK: - Delete File
    
    func deleteFile(diskImagePath: URL, fileName: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let diskData = NSMutableData(contentsOf: diskImagePath) else {
                    DispatchQueue.main.async {
                        completion(false, "Could not read disk image")
                    }
                    return
                }
                
                let dataOffset = self.get2MGDataOffset(Data(referencing: diskData))
                let isDOSOrder = self.isDOSOrderFloppy(Data(referencing: diskData), diskImagePath: diskImagePath)
                
                print("🗑️ Deleting file from ProDOS image:")
                print("   File: \(fileName)")
                print("   DOS Order: \(isDOSOrder)")
                
                // Find the file entry
                guard let (blockNum, entryOffsetInBlock) = self.findFileEntry(Data(referencing: diskData), fileName: fileName, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                    DispatchQueue.main.async {
                        completion(false, "File not found")
                    }
                    return
                }
                
                // Read the directory block
                guard var blockData = self.readBlock(Data(referencing: diskData), blockIndex: blockNum, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                    DispatchQueue.main.async {
                        completion(false, "Could not read directory block")
                    }
                    return
                }
                
                // Get file info before deleting
                let storageType = blockData[entryOffsetInBlock] >> 4
                let keyBlockLo = blockData[entryOffsetInBlock + 0x11]
                let keyBlockHi = blockData[entryOffsetInBlock + 0x12]
                let keyBlock = Int(keyBlockLo) | (Int(keyBlockHi) << 8)
                let blocksUsedLo = blockData[entryOffsetInBlock + 0x13]
                let blocksUsedHi = blockData[entryOffsetInBlock + 0x14]
                let blocksUsed = Int(blocksUsedLo) | (Int(blocksUsedHi) << 8)
                
                print("   📝 Storage type: \(storageType)")
                print("   📦 Blocks used: \(blocksUsed)")
                print("   🔑 Key block: \(keyBlock)")
                
                // Free all blocks used by the file
                var blocksToFree: [Int] = []
                
                if storageType == 1 {
                    // Seedling - just the data block
                    blocksToFree.append(keyBlock)
                } else if storageType == 2 {
                    // Sapling - index block + data blocks
                    if let indexBlockData = self.readBlock(Data(referencing: diskData), blockIndex: keyBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) {
                        for i in 0..<256 {
                            let ptrLo = indexBlockData[i]
                            let ptrHi = indexBlockData[256 + i]
                            let dataBlock = Int(ptrLo) | (Int(ptrHi) << 8)
                            if dataBlock != 0 {
                                blocksToFree.append(dataBlock)
                            }
                        }
                    }
                    blocksToFree.append(keyBlock)
                } else if storageType == 3 {
                    // Tree - master index + index blocks + data blocks
                    if let masterBlockData = self.readBlock(Data(referencing: diskData), blockIndex: keyBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) {
                        for i in 0..<256 {
                            let indexPtrLo = masterBlockData[i]
                            let indexPtrHi = masterBlockData[256 + i]
                            let indexBlock = Int(indexPtrLo) | (Int(indexPtrHi) << 8)
                            if indexBlock == 0 { continue }
                            
                            if let indexBlockData = self.readBlock(Data(referencing: diskData), blockIndex: indexBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) {
                                for j in 0..<256 {
                                    let dataPtrLo = indexBlockData[j]
                                    let dataPtrHi = indexBlockData[256 + j]
                                    let dataBlock = Int(dataPtrLo) | (Int(dataPtrHi) << 8)
                                    if dataBlock != 0 {
                                        blocksToFree.append(dataBlock)
                                    }
                                }
                            }
                            blocksToFree.append(indexBlock)
                        }
                    }
                    blocksToFree.append(keyBlock)
                } else if storageType == 0xD {
                    // Subdirectory
                    blocksToFree.append(keyBlock)
                    print("   📂 Deleting subdirectory (1 block)")
                }
                
                print("   🔓 Freeing \(blocksToFree.count) blocks")
                
                // Mark blocks as free in bitmap
                self.freeBlocks(diskData, blocks: blocksToFree, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                
                // Clear directory entry (mark as deleted)
                for i in 0..<self.ENTRY_LENGTH {
                    blockData[entryOffsetInBlock + i] = 0
                }
                
                // Write directory block back
                self.writeBlock(diskData, blockIndex: blockNum, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                
                // Decrement file count
                self.decrementFileCount(diskData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                
                // Write back to disk
                try diskData.write(to: diskImagePath, options: .atomic)
                
                DispatchQueue.main.async {
                    completion(true, "File deleted successfully")
                }
                
                print("   ✅ File deleted successfully")
            } catch {
                DispatchQueue.main.async {
                    completion(false, "Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Free Blocks
    
    private func freeBlocks(_ diskData: NSMutableData, blocks: [Int], dataOffset: Int, isDOSOrder: Bool) {
        let bitmapStartBlock = 6
        
        for block in blocks {
            let byteIndex = block / 8
            let bitPosition = 7 - (block % 8)
            
            let bitmapBlock = bitmapStartBlock + (byteIndex / BLOCK_SIZE)
            let bitmapByteOffset = byteIndex % BLOCK_SIZE
            
            guard var bitmapBlockData = readBlock(Data(referencing: diskData), blockIndex: bitmapBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                continue
            }
            
            bitmapBlockData[bitmapByteOffset] |= (1 << bitPosition)  // Set bit to 1 = free
            
            writeBlock(diskData, blockIndex: bitmapBlock, blockData: bitmapBlockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
        }
    }
    
    // MARK: - Decrement File Count
    
    private func decrementFileCount(_ diskData: NSMutableData, dataOffset: Int, isDOSOrder: Bool) {
        guard var blockData = readBlock(Data(referencing: diskData), blockIndex: VOLUME_DIR_BLOCK, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
            return
        }
        
        // Volume directory: file count at +$25-$26
        let fileCountOffset = 0x25
        
        let currentCountLo = Int(blockData[fileCountOffset])
        let currentCountHi = Int(blockData[fileCountOffset + 1])
        var fileCount = currentCountLo | (currentCountHi << 8)
        
        fileCount = max(0, fileCount - 1)
        
        blockData[fileCountOffset] = UInt8(fileCount & 0xFF)
        blockData[fileCountOffset + 1] = UInt8((fileCount >> 8) & 0xFF)
        
        writeBlock(diskData, blockIndex: VOLUME_DIR_BLOCK, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
        
        print("   📊 Updated file count: \(fileCount)")
    }
    
    // MARK: - Create Directory
    
    func createDirectory(diskImagePath: URL, directoryName: String, parentPath: String = "/", completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let sanitizedName = self.sanitizeProDOSFilename(directoryName)
            
            guard let diskData = NSMutableData(contentsOf: diskImagePath) else {
                DispatchQueue.main.async {
                    completion(false, "Could not read disk image")
                }
                return
            }
            
            let dataOffset = self.get2MGDataOffset(Data(referencing: diskData))
            let isDOSOrder = self.isDOSOrderFloppy(Data(referencing: diskData), diskImagePath: diskImagePath)
            
            // Find parent directory block
            guard let parentDirBlock = self.findDirectoryBlock(diskData, path: parentPath, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                DispatchQueue.main.async {
                    completion(false, "Parent directory not found: \(parentPath)")
                }
                return
            }
            
            print("   📂 Parent directory block: \(parentDirBlock) (path: \(parentPath))")
            
            // Find free directory entry in parent
            guard let (entryDirBlock, entryOffsetInBlock) = self.findFreeDirectoryEntry(diskData, dirBlock: parentDirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                DispatchQueue.main.async {
                    completion(false, "No free directory entries in \(parentPath)")
                }
                return
            }
            
            // Allocate a block for the new subdirectory
            guard let blocks = self.allocateBlocks(diskData, count: 1, dataOffset: dataOffset, isDOSOrder: isDOSOrder),
                  let dirBlock = blocks.first else {
                DispatchQueue.main.async {
                    completion(false, "Could not allocate block for directory")
                }
                return
            }
            
            print("📁 Creating directory '\(sanitizedName)' at block \(dirBlock)")
            
            // Create subdirectory header block
            self.createSubdirectoryHeader(diskData, dirBlock: dirBlock, dirName: sanitizedName, parentBlock: parentDirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
            
            // Create directory entry in parent
            self.createDirectoryEntryForSubdir(diskData, dirBlock: entryDirBlock, entryOffsetInBlock: entryOffsetInBlock, dirName: sanitizedName, keyBlock: dirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
            
            // Increment file count in parent directory
            self.incrementFileCount(diskData, dirBlock: parentDirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
            
            // Write back to disk
            guard diskData.write(to: diskImagePath, atomically: true) else {
                DispatchQueue.main.async {
                    completion(false, "Failed to write disk image")
                }
                return
            }
            
            print("✅ Directory '\(sanitizedName)' created successfully")
            
            DispatchQueue.main.async {
                completion(true, "Directory created")
            }
        }
    }
    
    // MARK: - Create Subdirectory Header
    
    private func createSubdirectoryHeader(_ diskData: NSMutableData, dirBlock: Int, dirName: String, parentBlock: Int, dataOffset: Int, isDOSOrder: Bool) {
        var blockData = Data(repeating: 0, count: BLOCK_SIZE)
        
        // +$00-01: Previous block (0x0000 for first block)
        blockData[0] = 0x00
        blockData[1] = 0x00
        
        // +$02-03: Next block (0x0000 - no next block initially)
        blockData[2] = 0x00
        blockData[3] = 0x00
        
        // +$04: Storage type (0xE = subdirectory header) + name length
        let nameLength = min(dirName.count, 15)
        blockData[4] = UInt8(0xE0 | nameLength)
        
        // +$05-$13: Directory name (15 bytes)
        for i in 0..<nameLength {
            let index = dirName.index(dirName.startIndex, offsetBy: i)
            blockData[5 + i] = UInt8(dirName[index].asciiValue ?? 0x20)
        }
        
        // +$1C-$1F: Creation date/time
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        
        if let year = components.year, let month = components.month, let day = components.day {
            let proDOSYear = year - 1900
            let dateWord = UInt16((proDOSYear << 9) | (month << 5) | day)
            blockData[0x1C] = UInt8(dateWord & 0xFF)
            blockData[0x1D] = UInt8((dateWord >> 8) & 0xFF)
        }
        
        if let hour = components.hour, let minute = components.minute {
            let timeWord = UInt16((minute << 8) | hour)
            blockData[0x1E] = UInt8(timeWord & 0xFF)
            blockData[0x1F] = UInt8((timeWord >> 8) & 0xFF)
        }
        
        // +$20: Version (0x00)
        blockData[0x20] = 0x00
        
        // +$21: Min version (0x00)
        blockData[0x21] = 0x00
        
        // +$22: Access (0xE3 = full access)
        blockData[0x22] = 0xE3
        
        // +$23: Entry length (0x27 = 39 bytes)
        blockData[0x23] = 0x27
        
        // +$24: Entries per block (0x0D = 13)
        blockData[0x24] = 0x0D
        
        // +$25-$26: File count (0x0000 initially - empty directory)
        blockData[0x25] = 0x00
        blockData[0x26] = 0x00
        
        // +$27-$28: Parent pointer (block number of parent directory)
        blockData[0x27] = UInt8(parentBlock & 0xFF)
        blockData[0x28] = UInt8((parentBlock >> 8) & 0xFF)
        
        // +$29: Parent entry number
        blockData[0x29] = 0x00
        
        // +$2A: Parent entry length (0x27)
        blockData[0x2A] = 0x27
        
        writeBlock(diskData, blockIndex: dirBlock, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
    }
    
    // MARK: - Create Directory Entry for Subdirectory
    
    private func createDirectoryEntryForSubdir(_ diskData: NSMutableData, dirBlock: Int, entryOffsetInBlock: Int, dirName: String, keyBlock: Int, dataOffset: Int, isDOSOrder: Bool) {
        guard var blockData = readBlock(Data(referencing: diskData), blockIndex: dirBlock, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
            return
        }
        
        let nameLength = min(dirName.count, 15)
        
        // Storage type 0xD = subdirectory
        blockData[entryOffsetInBlock] = UInt8(0xD0 | nameLength)
        
        // Name
        for i in 0..<nameLength {
            let index = dirName.index(dirName.startIndex, offsetBy: i)
            blockData[entryOffsetInBlock + 1 + i] = UInt8(dirName[index].asciiValue ?? 0x20)
        }
        
        // File type = 0x0F (directory)
        blockData[entryOffsetInBlock + 0x10] = 0x0F
        
        // Key block
        blockData[entryOffsetInBlock + 0x11] = UInt8(keyBlock & 0xFF)
        blockData[entryOffsetInBlock + 0x12] = UInt8((keyBlock >> 8) & 0xFF)
        
        // Blocks used = 1
        blockData[entryOffsetInBlock + 0x13] = 0x01
        blockData[entryOffsetInBlock + 0x14] = 0x00
        
        // EOF = 512 (1 block)
        blockData[entryOffsetInBlock + 0x15] = 0x00
        blockData[entryOffsetInBlock + 0x16] = 0x02
        blockData[entryOffsetInBlock + 0x17] = 0x00
        
        // Creation date/time
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        
        if let year = components.year, let month = components.month, let day = components.day {
            let proDOSYear = year - 1900
            let dateWord = UInt16((proDOSYear << 9) | (month << 5) | day)
            blockData[entryOffsetInBlock + 0x18] = UInt8(dateWord & 0xFF)
            blockData[entryOffsetInBlock + 0x19] = UInt8((dateWord >> 8) & 0xFF)
        }
        
        if let hour = components.hour, let minute = components.minute {
            let timeWord = UInt16((minute << 8) | hour)
            blockData[entryOffsetInBlock + 0x1A] = UInt8(timeWord & 0xFF)
            blockData[entryOffsetInBlock + 0x1B] = UInt8((timeWord >> 8) & 0xFF)
        }
        
        // Version, min version
        blockData[entryOffsetInBlock + 0x1C] = 0x00
        blockData[entryOffsetInBlock + 0x1D] = 0x00
        
        // Access
        blockData[entryOffsetInBlock + 0x1E] = 0xE3
        
        // Aux type = 0x0000 for directories
        blockData[entryOffsetInBlock + 0x1F] = 0x00
        blockData[entryOffsetInBlock + 0x20] = 0x00
        
        // Last mod = creation
        blockData[entryOffsetInBlock + 0x21] = blockData[entryOffsetInBlock + 0x18]
        blockData[entryOffsetInBlock + 0x22] = blockData[entryOffsetInBlock + 0x19]
        blockData[entryOffsetInBlock + 0x23] = blockData[entryOffsetInBlock + 0x1A]
        blockData[entryOffsetInBlock + 0x24] = blockData[entryOffsetInBlock + 0x1B]
        
        // Header pointer
        blockData[entryOffsetInBlock + 0x25] = UInt8(keyBlock & 0xFF)
        blockData[entryOffsetInBlock + 0x26] = UInt8((keyBlock >> 8) & 0xFF)
        
        writeBlock(diskData, blockIndex: dirBlock, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
    }
    
    // MARK: - Rename File
    
    func renameFile(diskImagePath: URL, oldName: String, newName: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let diskData = NSMutableData(contentsOf: diskImagePath) else {
                    DispatchQueue.main.async {
                        completion(false, "Could not read disk image")
                    }
                    return
                }
                
                let dataOffset = self.get2MGDataOffset(Data(referencing: diskData))
                let isDOSOrder = self.isDOSOrderFloppy(Data(referencing: diskData), diskImagePath: diskImagePath)
                
                print("✏️ Renaming file in ProDOS image:")
                print("   Old name: \(oldName)")
                print("   New name: \(newName)")
                
                // Find the file entry
                guard let (blockNum, entryOffsetInBlock) = self.findFileEntry(Data(referencing: diskData), fileName: oldName, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                    DispatchQueue.main.async {
                        completion(false, "File '\(oldName)' not found")
                    }
                    return
                }
                
                // Sanitize new name
                let sanitizedName = self.sanitizeProDOSFilename(newName)
                print("   Sanitized name: \(sanitizedName)")
                
                // Check if new name already exists
                if let _ = self.findFileEntry(Data(referencing: diskData), fileName: sanitizedName, dataOffset: dataOffset, isDOSOrder: isDOSOrder) {
                    DispatchQueue.main.async {
                        completion(false, "A file named '\(sanitizedName)' already exists")
                    }
                    return
                }
                
                // Read directory block
                guard var blockData = self.readBlock(Data(referencing: diskData), blockIndex: blockNum, dataOffset: dataOffset, isDOSOrder: isDOSOrder) else {
                    DispatchQueue.main.async {
                        completion(false, "Could not read directory block")
                    }
                    return
                }
                
                // Get storage type from first byte
                let storageTypeAndLength = blockData[entryOffsetInBlock]
                let storageType = storageTypeAndLength >> 4
                
                // Update storage type + name length byte
                let nameLen = min(sanitizedName.count, 15)
                blockData[entryOffsetInBlock] = (storageType << 4) | UInt8(nameLen)
                
                // Clear old name (15 bytes)
                for i in 0..<15 {
                    blockData[entryOffsetInBlock + 1 + i] = 0x00
                }
                
                // Write new name
                for (i, char) in sanitizedName.uppercased().prefix(15).enumerated() {
                    blockData[entryOffsetInBlock + 1 + i] = UInt8(char.asciiValue ?? 0x20)
                }
                
                print("   📝 Updated filename at block \(blockNum)")
                
                // Write block back
                self.writeBlock(diskData, blockIndex: blockNum, blockData: blockData, dataOffset: dataOffset, isDOSOrder: isDOSOrder)
                
                // Write to disk
                try diskData.write(to: diskImagePath, options: .atomic)
                
                DispatchQueue.main.async {
                    completion(true, "File renamed successfully")
                }
                
                print("   ✅ File renamed successfully!")
                
            } catch {
                DispatchQueue.main.async {
                    completion(false, "Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Create Disk Image
    
    func createDiskImage(at path: URL, volumeName: String, sizeString: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let totalBlocks: Int
                if sizeString.uppercased().contains("MB") {
                    let mb = Int(sizeString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 32
                    let calculatedBlocks = (mb * 1024 * 1024) / self.BLOCK_SIZE
                    totalBlocks = min(calculatedBlocks, 65535)
                } else if sizeString.uppercased().contains("KB") {
                    let kb = Int(sizeString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 800
                    let calculatedBlocks = (kb * 1024) / self.BLOCK_SIZE
                    totalBlocks = min(calculatedBlocks, 65535)
                } else {
                    totalBlocks = 65535
                }
                
                print("📝 Creating ProDOS disk image:")
                print("   Path: \(path.path)")
                print("   Volume: \(volumeName)")
                print("   Blocks: \(totalBlocks)")
                
                let diskData = NSMutableData(length: totalBlocks * self.BLOCK_SIZE)!
                
                // Note: New disk images are created in ProDOS order (linear), not DOS order
                self.createBootBlocks(diskData)
                self.createVolumeDirectory(diskData, volumeName: volumeName, totalBlocks: totalBlocks)
                self.createBitmap(diskData, totalBlocks: totalBlocks)
                
                try diskData.write(to: path, options: .atomic)
                
                print("   ✅ Disk image created successfully!")
                
                DispatchQueue.main.async {
                    completion(true, "Disk image created successfully")
                }
                
            } catch {
                print("   ❌ Error: \(error)")
                DispatchQueue.main.async {
                    completion(false, "Error creating disk: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Create Boot Blocks
    
    private func createBootBlocks(_ diskData: NSMutableData) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        
        // Standard ProDOS boot loader (first 512 bytes)
        let bootCode: [UInt8] = [
            0x01, 0x38, 0xB0, 0x03, 0x4C, 0x32, 0xA1, 0x86, 0x43, 0xC9, 0x03, 0x08, 0x8A, 0x29, 0x70, 0x4A,
            0x4A, 0x4A, 0x4A, 0x09, 0xC0, 0x85, 0x49, 0xA0, 0xFF, 0x84, 0x48, 0x28, 0xC8, 0xB1, 0x48, 0xD0,
            0x3A, 0xB0, 0x0E, 0xA9, 0x03, 0x8D, 0x00, 0x08, 0xE6, 0x3D, 0xA5, 0x49, 0x48, 0xA9, 0x5B, 0x48,
            0x60, 0x85, 0x40, 0x85, 0x48, 0xA0, 0x63, 0xB1, 0x48, 0x99, 0x94, 0x09, 0xC8, 0xC0, 0xEB, 0xD0,
            0xF6, 0xA2, 0x06, 0xBC, 0x1D, 0x09, 0xBD, 0x24, 0x09, 0x99, 0xF2, 0x09, 0xBD, 0x2B, 0x09, 0x9D,
            0x7F, 0x0A, 0xCA, 0x10, 0xEE, 0xA9, 0x09, 0x85, 0x49, 0xA9, 0x86, 0xA0, 0x00, 0xC9, 0xF9, 0xB0,
            0x2F, 0x85, 0x48, 0x84, 0x60, 0x84, 0x4A, 0x84, 0x4C, 0x84, 0x4E, 0x84, 0x47, 0xC8, 0x84, 0x42,
            0xC8, 0x84, 0x46, 0xA9, 0x0C, 0x85, 0x61, 0x85, 0x4B, 0x20, 0x12, 0x09, 0xB0, 0x68, 0xE6, 0x61
        ]
        
        for (i, byte) in bootCode.enumerated() {
            bytes[i] = byte
        }
    }
    
    // MARK: - Create Volume Directory
    
    private func createVolumeDirectory(_ diskData: NSMutableData, volumeName: String, totalBlocks: Int) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let blockOffset = VOLUME_DIR_BLOCK * BLOCK_SIZE
        
        // Clear the block
        memset(bytes + blockOffset, 0, BLOCK_SIZE)
        
        // +$00-01: Previous block (0x0000)
        bytes[blockOffset + 0] = 0x00
        bytes[blockOffset + 1] = 0x00
        
        // +$02-03: Next block (block 3 for volume directory)
        bytes[blockOffset + 2] = 0x03
        bytes[blockOffset + 3] = 0x00
        
        // +$04: Storage type (0xF = volume header) + name length
        let nameLength = min(volumeName.count, 15)
        bytes[blockOffset + 4] = UInt8(0xF0 | nameLength)
        
        // +$05-$13: Volume name (15 bytes)
        for i in 0..<nameLength {
            let index = volumeName.index(volumeName.startIndex, offsetBy: i)
            bytes[blockOffset + 5 + i] = UInt8(volumeName[index].asciiValue ?? 0x20)
        }
        
        // Creation date/time
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        
        if let year = components.year, let month = components.month, let day = components.day {
            let proDOSYear = year - 1900
            let dateWord = UInt16((proDOSYear << 9) | (month << 5) | day)
            bytes[blockOffset + 0x1C] = UInt8(dateWord & 0xFF)
            bytes[blockOffset + 0x1D] = UInt8((dateWord >> 8) & 0xFF)
        }
        
        if let hour = components.hour, let minute = components.minute {
            let timeWord = UInt16((minute << 8) | hour)
            bytes[blockOffset + 0x1E] = UInt8(timeWord & 0xFF)
            bytes[blockOffset + 0x1F] = UInt8((timeWord >> 8) & 0xFF)
        }
        
        // +$20: Version (0x00)
        bytes[blockOffset + 0x20] = 0x00
        
        // +$21: Min version (0x00)
        bytes[blockOffset + 0x21] = 0x00
        
        // +$22: Access (0xC3)
        bytes[blockOffset + 0x22] = 0xC3
        
        // +$23: Entry length (0x27 = 39)
        bytes[blockOffset + 0x23] = 0x27
        
        // +$24: Entries per block (0x0D = 13)
        bytes[blockOffset + 0x24] = 0x0D
        
        // +$25-$26: File count (0x0000)
        bytes[blockOffset + 0x25] = 0x00
        bytes[blockOffset + 0x26] = 0x00
        
        // +$27-$28: Bitmap pointer (block 6)
        bytes[blockOffset + 0x27] = 0x06
        bytes[blockOffset + 0x28] = 0x00
        
        // +$29-$2A: Total blocks
        bytes[blockOffset + 0x29] = UInt8(totalBlocks & 0xFF)
        bytes[blockOffset + 0x2A] = UInt8((totalBlocks >> 8) & 0xFF)
        
        // Create additional directory blocks (3, 4, 5)
        for additionalBlock in 3...5 {
            let addBlockOffset = additionalBlock * BLOCK_SIZE
            memset(bytes + addBlockOffset, 0, BLOCK_SIZE)
            
            // Previous block
            bytes[addBlockOffset + 0] = UInt8((additionalBlock - 1) & 0xFF)
            bytes[addBlockOffset + 1] = 0x00
            
            // Next block (0 for last block)
            if additionalBlock < 5 {
                bytes[addBlockOffset + 2] = UInt8((additionalBlock + 1) & 0xFF)
                bytes[addBlockOffset + 3] = 0x00
            }
        }
    }
    
    // MARK: - Create Bitmap
    
    private func createBitmap(_ diskData: NSMutableData, totalBlocks: Int) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let bitmapStartBlock = 6
        let bitmapBytes = (totalBlocks + 7) / 8
        let bitmapBlocks = (bitmapBytes + BLOCK_SIZE - 1) / BLOCK_SIZE
        
        print("   🗺️  Creating bitmap: \(bitmapBlocks) blocks")
        
        let bitmapOffset = bitmapStartBlock * BLOCK_SIZE
        memset(bytes + bitmapOffset, 0xFF, bitmapBytes)
        
        let systemBlocks = 6 + bitmapBlocks
        for block in 0..<systemBlocks {
            let byteIndex = block / 8
            let bitPosition = 7 - (block % 8)
            bytes[bitmapOffset + byteIndex] &= ~(1 << bitPosition)
        }
        
        print("   ✅ Marked blocks 0-\(systemBlocks - 1) as used")
    }
}
