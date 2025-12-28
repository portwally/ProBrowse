//
//  ProDOSWriter.swift
//  ProBrowse
//
//  Direct ProDOS disk image manipulation without external tools
//

import Foundation

class ProDOSWriter {
    static let shared = ProDOSWriter()
    
    private let BLOCK_SIZE = 512
    private let VOLUME_DIR_BLOCK = 2
    private let ENTRIES_PER_BLOCK = 13  // 0x0D
    private let ENTRY_LENGTH = 39       // 0x27
    
    private init() {}
    
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
                
                // Check if filename already exists and rename if needed
                var finalName = sanitizedName
                var counter = 1
                while self.fileExists(diskData, fileName: finalName) {
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
                
                // Find target directory block
                guard let targetDirBlock = self.findDirectoryBlock(diskData, path: parentPath) else {
                    DispatchQueue.main.async {
                        completion(false, "Parent directory not found: \(parentPath)")
                    }
                    return
                }
                
                print("   📂 Target directory block: \(targetDirBlock)")
                
                // 1. Find free directory entry in target directory
                guard let (dirBlock, entryOffset) = self.findFreeDirectoryEntry(diskData, dirBlock: targetDirBlock) else {
                    DispatchQueue.main.async {
                        completion(false, "No free directory entries in \(parentPath)")
                    }
                    return
                }
                
                print("   📂 Free entry at block \(dirBlock), offset \(entryOffset)")
                
                // 2. Allocate blocks for file data
                let blocksNeeded = (fileData.count + self.BLOCK_SIZE - 1) / self.BLOCK_SIZE
                guard let dataBlocks = self.allocateBlocks(diskData, count: blocksNeeded) else {
                    DispatchQueue.main.async {
                        completion(false, "Not enough free blocks (need \(blocksNeeded))")
                    }
                    return
                }
                
                print("   💾 Allocated \(blocksNeeded) blocks: \(dataBlocks)")
                
                // 3. Write file data to allocated blocks
                self.writeFileData(diskData, fileData: fileData, blocks: dataBlocks)
                
                // 4. For sapling/tree files, create index block(s)
                var keyBlock = dataBlocks[0]  // Default for seedling
                var totalBlocks = dataBlocks.count
                
                if dataBlocks.count > 256 {
                    // Tree file - need master index + multiple index blocks
                    let numIndexBlocks = (dataBlocks.count + 255) / 256  // Round up
                    
                    guard let indexBlocks = self.allocateBlocks(diskData, count: numIndexBlocks) else {
                        DispatchQueue.main.async {
                            completion(false, "Could not allocate index blocks")
                        }
                        return
                    }
                    
                    guard let masterIndexBlocks = self.allocateBlocks(diskData, count: 1) else {
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
                        self.createIndexBlock(diskData, indexBlock: indexBlocks[i], dataBlocks: blocksForThisIndex)
                    }
                    
                    // Create master index block pointing to index blocks
                    self.createMasterIndexBlock(diskData, masterIndexBlock: keyBlock, indexBlocks: indexBlocks)
                    print("   🌳 Created tree file: master index at \(keyBlock), \(numIndexBlocks) index blocks")
                    
                } else if dataBlocks.count > 1 {
                    // Sapling file - need one index block
                    guard let indexBlocks = self.allocateBlocks(diskData, count: 1) else {
                        DispatchQueue.main.async {
                            completion(false, "Could not allocate index block")
                        }
                        return
                    }
                    keyBlock = indexBlocks[0]
                    totalBlocks += 1  // Include index block in count
                    self.createIndexBlock(diskData, indexBlock: keyBlock, dataBlocks: dataBlocks)
                    print("   📇 Created index block at \(keyBlock)")
                }
                
                // 5. Create directory entry
                self.createDirectoryEntry(diskData, dirBlock: dirBlock, entryOffset: entryOffset,
                                        fileName: finalName, fileType: fileType, auxType: auxType,
                                        keyBlock: keyBlock, blockCount: totalBlocks, fileSize: fileData.count)
                
                // 5. Update file count in target directory
                self.incrementFileCount(diskData, dirBlock: targetDirBlock)
                
                // 6. Write modified disk image back to file
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
    private func createMasterIndexBlock(_ diskData: NSMutableData, masterIndexBlock: Int, indexBlocks: [Int]) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let offset = masterIndexBlock * BLOCK_SIZE
        
        // Clear the block
        memset(bytes + offset, 0, BLOCK_SIZE)
        
        // Write index block pointers
        // Format: first 256 bytes are low bytes, second 256 bytes are high bytes
        for i in 0..<min(indexBlocks.count, 256) {
            let block = indexBlocks[i]
            bytes[offset + i] = UInt8(block & 0xFF)
            bytes[offset + 256 + i] = UInt8((block >> 8) & 0xFF)
        }
    }
    
    /// Creates an index block for sapling files (storage type 2)
    private func createIndexBlock(_ diskData: NSMutableData, indexBlock: Int, dataBlocks: [Int]) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let offset = indexBlock * BLOCK_SIZE
        
        // Clear the block
        memset(bytes + offset, 0, BLOCK_SIZE)
        
        // Write data block pointers
        // Format: first 256 bytes are low bytes, second 256 bytes are high bytes
        for i in 0..<min(dataBlocks.count, 256) {
            let block = dataBlocks[i]
            bytes[offset + i] = UInt8(block & 0xFF)
            bytes[offset + 256 + i] = UInt8((block >> 8) & 0xFF)
        }
    }
    
    // MARK: - Find Free Directory Entry
    
    // MARK: - Find Directory Block by Path
    
    /// Finds the directory block for a given path
    /// - Parameter path: Directory path (e.g., "/" for root, "/SYSTEM" for subdirectory)
    /// - Returns: Block number of the directory, or nil if not found
    private func findDirectoryBlock(_ diskData: NSMutableData, path: String) -> Int? {
        // Root directory
        if path == "/" {
            return VOLUME_DIR_BLOCK
        }
        
        // Parse path components (e.g., "/SYSTEM/FSTS" -> ["SYSTEM", "FSTS"])
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return VOLUME_DIR_BLOCK }
        
        let bytes = diskData.bytes.assumingMemoryBound(to: UInt8.self)
        var currentDirBlock = VOLUME_DIR_BLOCK
        
        // Navigate through each path component
        for dirName in components {
            guard let (_, entryOffset) = findFileEntryInDirectory(diskData, dirBlock: currentDirBlock, fileName: dirName) else {
                print("   ❌ Directory '\(dirName)' not found in path")
                return nil
            }
            
            // Check if it's actually a directory
            let storageType = bytes[entryOffset] >> 4
            guard storageType == 0xD else {
                print("   ❌ '\(dirName)' is not a directory (storage type: \(storageType))")
                return nil
            }
            
            // Get the subdirectory's block
            let keyBlockLo = bytes[entryOffset + 0x11]
            let keyBlockHi = bytes[entryOffset + 0x12]
            currentDirBlock = Int(keyBlockLo) | (Int(keyBlockHi) << 8)
        }
        
        return currentDirBlock
    }
    
    /// Finds a file entry within a specific directory block
    private func findFileEntryInDirectory(_ diskData: NSMutableData, dirBlock: Int, fileName: String) -> (block: Int, offset: Int)? {
        let bytes = diskData.bytes.assumingMemoryBound(to: UInt8.self)
        var currentBlock = dirBlock
        var entryIndex = 1  // Skip header entry
        
        while currentBlock != 0 {
            let blockOffset = currentBlock * BLOCK_SIZE
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = blockOffset + 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = bytes[entryOffset] >> 4
                
                if storageType != 0 {
                    // Read entry name
                    let nameLength = Int(bytes[entryOffset] & 0x0F)
                    let nameBytes = Array(UnsafeBufferPointer(start: bytes + entryOffset + 1, count: min(nameLength, 15)))
                    let entryName = String(bytes: nameBytes, encoding: .ascii) ?? ""
                    
                    if entryName.uppercased() == fileName.uppercased() {
                        return (currentBlock, entryOffset)
                    }
                }
                
                entryIndex += 1
            }
            
            // Move to next block in directory chain
            let nextBlockLo = Int(bytes[blockOffset + 2])
            let nextBlockHi = Int(bytes[blockOffset + 3])
            currentBlock = nextBlockLo | (nextBlockHi << 8)
            entryIndex = 0
        }
        
        return nil
    }
    
    private func findFreeDirectoryEntry(_ diskData: NSMutableData, dirBlock: Int? = nil) -> (block: Int, offset: Int)? {
        let bytes = diskData.bytes.assumingMemoryBound(to: UInt8.self)
        var currentBlock = dirBlock ?? VOLUME_DIR_BLOCK
        var entryIndex = 1  // Skip header entry
        
        while currentBlock != 0 {
            let blockOffset = currentBlock * BLOCK_SIZE
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = blockOffset + 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = bytes[entryOffset] >> 4
                
                if storageType == 0 {
                    return (currentBlock, entryOffset)
                }
                
                entryIndex += 1
            }
            
            let nextBlockLo = Int(bytes[blockOffset + 2])
            let nextBlockHi = Int(bytes[blockOffset + 3])
            currentBlock = nextBlockLo | (nextBlockHi << 8)
            entryIndex = 0
        }
        
        return nil
    }
    
    // MARK: - Allocate Blocks
    
    private func allocateBlocks(_ diskData: NSMutableData, count: Int) -> [Int]? {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let dataOffset = get2MGDataOffset(Data(referencing: diskData))
        
        var allocatedBlocks: [Int] = []
        
        let startBlock = 24
        let volHeaderOffset = dataOffset + VOLUME_DIR_BLOCK * BLOCK_SIZE
        let totalBlocksLo = Int(bytes[volHeaderOffset + 0x29])
        let totalBlocksHi = Int(bytes[volHeaderOffset + 0x2A])
        let totalBlocks = totalBlocksLo | (totalBlocksHi << 8)
        
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
            
            let bitmapBlock = bitmapStartBlock + (byteIndex / BLOCK_SIZE)
            let bitmapByteOffset = byteIndex % BLOCK_SIZE
            let bitmapOffset = dataOffset + bitmapBlock * BLOCK_SIZE + bitmapByteOffset
            
            let bitmapByte = bytes[bitmapOffset]
            let isFree = (bitmapByte & (1 << bitPosition)) != 0
            
            if isFree {
                allocatedBlocks.append(block)
                bytes[bitmapOffset] = bitmapByte & ~(1 << bitPosition)
            }
        }
        
        if allocatedBlocks.count < count {
            return nil
        }
        
        return allocatedBlocks
    }
    
    // MARK: - Write File Data (FIXED with memcpy)
    
    private func writeFileData(_ diskData: NSMutableData, fileData: Data, blocks: [Int]) {
        print("   📝 Writing \(fileData.count) bytes to \(blocks.count) blocks")
        
        let diskBytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        
        fileData.withUnsafeBytes { (fileBytes: UnsafeRawBufferPointer) in
            guard let fileBaseAddress = fileBytes.baseAddress else { return }
            
            var dataOffset = 0
            
            for (index, block) in blocks.enumerated() {
                let blockOffset = block * BLOCK_SIZE
                let bytesToWrite = min(BLOCK_SIZE, fileData.count - dataOffset)
                
                print("   📦 Block \(index): block#\(block), writing \(bytesToWrite) bytes")
                
                // Copy file data to disk using memcpy
                memcpy(diskBytes + blockOffset, fileBaseAddress + dataOffset, bytesToWrite)
                
                // Zero-fill rest of block if needed
                if bytesToWrite < BLOCK_SIZE {
                    memset(diskBytes + blockOffset + bytesToWrite, 0, BLOCK_SIZE - bytesToWrite)
                }
                
                dataOffset += bytesToWrite
            }
            
            print("   ✅ Wrote \(dataOffset) bytes total")
        }
    }
    
    // MARK: - Create Directory Entry
    
    private func createDirectoryEntry(_ diskData: NSMutableData, dirBlock: Int, entryOffset: Int,
                                     fileName: String, fileType: UInt8, auxType: UInt16,
                                     keyBlock: Int, blockCount: Int, fileSize: Int) {
        
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        
        let storageType: UInt8
        if blockCount == 1 {
            storageType = 1  // Seedling
        } else if blockCount <= 256 {
            storageType = 2  // Sapling (has index block)
        } else {
            storageType = 3  // Tree (has master index)
        }
        
        var nameBytes = [UInt8](repeating: 0x00, count: 15)  // Pad with 0x00
        let nameData = fileName.uppercased().data(using: .ascii) ?? Data()
        let nameLen = min(nameData.count, 15)
        for i in 0..<nameLen {
            // Directory entry names use PLAIN ASCII (no high bit)
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
        
        // Bytes 0x25-0x26: Header pointer (only for subdirectories)
        // For regular files, should be 0x00 0x00 or last mod date
        entry[0x25] = 0x00
        entry[0x26] = 0x00
        
        memcpy(bytes + entryOffset, entry, ENTRY_LENGTH)
    }
    
    // MARK: - Create Directory
    
    /// Creates a new subdirectory in the disk image
    func createDirectory(diskImagePath: URL, directoryName: String, parentPath: String = "/", completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Sanitize directory name
            let sanitizedName = self.sanitizeProDOSFilename(directoryName)
            
            // Load disk image
            guard let diskData = NSMutableData(contentsOf: diskImagePath) else {
                DispatchQueue.main.async {
                    completion(false, "Could not read disk image")
                }
                return
            }
            
            let dataOffset = self.get2MGDataOffset(Data(referencing: diskData))
            
            // Find parent directory block using path
            guard let parentDirBlock = self.findDirectoryBlock(diskData, path: parentPath) else {
                DispatchQueue.main.async {
                    completion(false, "Parent directory not found: \(parentPath)")
                }
                return
            }
            
            print("   📂 Parent directory block: \(parentDirBlock) (path: \(parentPath))")
            
            // Find free directory entry in parent
            guard let (entryDirBlock, entryOffset) = self.findFreeDirectoryEntry(diskData, dirBlock: parentDirBlock) else {
                DispatchQueue.main.async {
                    completion(false, "No free directory entries in \(parentPath)")
                }
                return
            }
            
            // Allocate a block for the new subdirectory
            guard let blocks = self.allocateBlocks(diskData, count: 1),
                  let dirBlock = blocks.first else {
                DispatchQueue.main.async {
                    completion(false, "Could not allocate block for directory")
                }
                return
            }
            
            print("📁 Creating directory '\(sanitizedName)' at block \(dirBlock)")
            
            // Create subdirectory header block
            self.createSubdirectoryHeader(diskData, dirBlock: dirBlock, dirName: sanitizedName, parentBlock: parentDirBlock, parentEntryNum: 0, dataOffset: dataOffset)
            
            // Create directory entry in parent
            self.createDirectoryEntryForSubdir(diskData, dirBlock: entryDirBlock, entryOffset: entryOffset, dirName: sanitizedName, keyBlock: dirBlock, dataOffset: dataOffset)
            
            // Increment file count in parent directory
            self.incrementFileCount(diskData, dirBlock: parentDirBlock)
            
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
    
    private func createSubdirectoryHeader(_ diskData: NSMutableData, dirBlock: Int, dirName: String, parentBlock: Int, parentEntryNum: Int, dataOffset: Int) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let blockOffset = dataOffset + (dirBlock * BLOCK_SIZE)
        
        // Clear the block
        memset(bytes + blockOffset, 0, BLOCK_SIZE)
        
        // +$00-01: Previous block (0x0000 for first block)
        bytes[blockOffset + 0] = 0x00
        bytes[blockOffset + 1] = 0x00
        
        // +$02-03: Next block (0x0000 - no next block initially)
        bytes[blockOffset + 2] = 0x00
        bytes[blockOffset + 3] = 0x00
        
        // +$04: Storage type (0xE = subdirectory header) + name length
        let nameLength = min(dirName.count, 15)
        bytes[blockOffset + 4] = UInt8(0xE0 | nameLength)
        
        // +$05-$13: Directory name (15 bytes)
        for i in 0..<nameLength {
            let index = dirName.index(dirName.startIndex, offsetBy: i)
            bytes[blockOffset + 5 + i] = UInt8(dirName[index].asciiValue ?? 0x20)
        }
        
        // +$14-$1B: Reserved (8 bytes) - zeros
        
        // +$1C-$1F: Creation date/time
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
        
        // +$21: Access (0xE3 = full access)
        bytes[blockOffset + 0x21] = 0xE3
        
        // +$22: Entry length (0x27 = 39 bytes)
        bytes[blockOffset + 0x22] = 0x27
        
        // +$23: Entries per block (0x0D = 13)
        bytes[blockOffset + 0x23] = 0x0D
        
        // +$24-$25: File count (0x0000 initially - empty directory)
        bytes[blockOffset + 0x24] = 0x00
        bytes[blockOffset + 0x25] = 0x00
        
        // +$26-$27: Parent pointer (block number of parent directory)
        bytes[blockOffset + 0x26] = UInt8(parentBlock & 0xFF)
        bytes[blockOffset + 0x27] = UInt8((parentBlock >> 8) & 0xFF)
        
        // +$28: Parent entry number (which entry in parent points to this subdir)
        bytes[blockOffset + 0x28] = UInt8(parentEntryNum)
        
        // +$29: Parent entry length (0x27)
        bytes[blockOffset + 0x29] = 0x27
        
        print("   📝 Created subdirectory header at block \(dirBlock)")
    }
    
    // MARK: - Create Directory Entry for Subdirectory
    
    private func createDirectoryEntryForSubdir(_ diskData: NSMutableData, dirBlock: Int, entryOffset: Int, dirName: String, keyBlock: Int, dataOffset: Int) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        var entry = [UInt8](repeating: 0, count: ENTRY_LENGTH)
        
        // Storage type (0xD = subdirectory) + name length
        let nameLength = min(dirName.count, 15)
        entry[0] = UInt8(0xD0 | nameLength)
        
        // File name (bytes 1-15)
        for i in 0..<nameLength {
            let index = dirName.index(dirName.startIndex, offsetBy: i)
            entry[1 + i] = UInt8(dirName[index].asciiValue ?? 0x20)
        }
        
        // File type: 0x0F (DIR)
        entry[0x10] = 0x0F
        
        // Key pointer: block number of subdirectory
        entry[0x11] = UInt8(keyBlock & 0xFF)
        entry[0x12] = UInt8((keyBlock >> 8) & 0xFF)
        
        // Blocks used: 1 block initially
        entry[0x13] = 0x01
        entry[0x14] = 0x00
        
        // EOF: 512 bytes (one block)
        entry[0x15] = 0x00
        entry[0x16] = 0x02  // 512 = 0x0200
        entry[0x17] = 0x00
        
        // Creation date/time
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        
        if let year = components.year, let month = components.month, let day = components.day {
            let proDOSYear = year - 1900
            let dateWord = UInt16((proDOSYear << 9) | (month << 5) | day)
            entry[0x18] = UInt8(dateWord & 0xFF)
            entry[0x19] = UInt8((dateWord >> 8) & 0xFF)
        }
        
        if let hour = components.hour, let minute = components.minute {
            let timeWord = UInt16((minute << 8) | hour)
            entry[0x1A] = UInt8(timeWord & 0xFF)
            entry[0x1B] = UInt8((timeWord >> 8) & 0xFF)
        }
        
        // Version: 0x00
        entry[0x1C] = 0x00
        
        // Min version: 0x00
        entry[0x1D] = 0x00
        
        // Access: 0xE3 (full access)
        entry[0x1E] = 0xE3
        
        // Aux type: 0x0000 for directories
        entry[0x1F] = 0x00
        entry[0x20] = 0x00
        
        // Last modified date (same as creation)
        entry[0x21] = entry[0x18]
        entry[0x22] = entry[0x19]
        entry[0x23] = entry[0x1A]
        entry[0x24] = entry[0x1B]
        
        // Header pointer (for subdirectories, points to self)
        entry[0x25] = UInt8(keyBlock & 0xFF)
        entry[0x26] = UInt8((keyBlock >> 8) & 0xFF)
        
        memcpy(bytes + entryOffset, entry, ENTRY_LENGTH)
        
        print("   📝 Created directory entry for '\(dirName)' at offset \(entryOffset)")
    }
    
    // MARK: - Update File Count
    
    private func incrementFileCount(_ diskData: NSMutableData, dirBlock: Int? = nil) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let targetDirBlock = dirBlock ?? VOLUME_DIR_BLOCK
        let dirHeaderOffset = targetDirBlock * BLOCK_SIZE
        let fileCountOffset = dirHeaderOffset + 0x25
        
        let currentCountLo = Int(bytes[fileCountOffset])
        let currentCountHi = Int(bytes[fileCountOffset + 1])
        var fileCount = currentCountLo | (currentCountHi << 8)
        
        fileCount += 1
        
        bytes[fileCountOffset] = UInt8(fileCount & 0xFF)
        bytes[fileCountOffset + 1] = UInt8((fileCount >> 8) & 0xFF)
        
        print("   📊 Updated file count in block \(targetDirBlock): \(fileCount)")
    }
    
    // MARK: - Extract File
    
    func extractFile(diskImagePath: URL, fileName: String, completion: @escaping (Bool, Data?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let diskData = try? Data(contentsOf: diskImagePath) else {
                DispatchQueue.main.async {
                    completion(false, nil)
                }
                return
            }
            
            print("📤 Extracting file from ProDOS image:")
            print("   File: \(fileName)")
            
            guard let (_, entryOffset) = self.findFileEntry(diskData, fileName: fileName) else {
                print("   ❌ File not found")
                DispatchQueue.main.async {
                    completion(false, nil)
                }
                return
            }
            
            let storageType = diskData[entryOffset] >> 4
            let keyBlockLo = diskData[entryOffset + 0x11]
            let keyBlockHi = diskData[entryOffset + 0x12]
            let keyBlock = Int(keyBlockLo) | (Int(keyBlockHi) << 8)
            
            let sizeLo = diskData[entryOffset + 0x15]
            let sizeMid = diskData[entryOffset + 0x16]
            let sizeHi = diskData[entryOffset + 0x17]
            let fileSize = Int(sizeLo) | (Int(sizeMid) << 8) | (Int(sizeHi) << 16)
            
            print("   📝 Storage type: \(storageType)")
            print("   📍 Key block: \(keyBlock)")
            print("   📏 File size: \(fileSize) bytes")
            
            var fileData = Data()
            
            if storageType == 1 {
                // Seedling file (single block)
                let blockOffset = keyBlock * self.BLOCK_SIZE
                fileData = diskData[blockOffset..<(blockOffset + min(fileSize, self.BLOCK_SIZE))]
            } else if storageType == 2 {
                // Sapling file (index block points to data blocks)
                let indexBlockOffset = keyBlock * self.BLOCK_SIZE
                var remainingSize = fileSize
                
                for i in 0..<256 {
                    if remainingSize <= 0 { break }
                    
                    // ProDOS format: bytes 0-255 are low bytes, bytes 256-511 are high bytes
                    let ptrLo = diskData[indexBlockOffset + i]
                    let ptrHi = diskData[indexBlockOffset + 256 + i]
                    let dataBlock = Int(ptrLo) | (Int(ptrHi) << 8)
                    
                    if dataBlock == 0 { break }
                    
                    let blockOffset = dataBlock * self.BLOCK_SIZE
                    let bytesToRead = min(self.BLOCK_SIZE, remainingSize)
                    fileData.append(diskData[blockOffset..<(blockOffset + bytesToRead)])
                    remainingSize -= bytesToRead
                }
            } else if storageType == 3 {
                // Tree file (master index block points to index blocks)
                let masterIndexOffset = keyBlock * self.BLOCK_SIZE
                var remainingSize = fileSize
                
                print("   🌳 Tree file - master index at block \(keyBlock)")
                
                // Master index has 256 index block pointers
                // Format: first 256 bytes are low bytes, second 256 bytes are high bytes
                var indexBlockCount = 0
                for i in 0..<256 {
                    if remainingSize <= 0 { break }
                    
                    let indexBlockPtrLo = diskData[masterIndexOffset + i]
                    let indexBlockPtrHi = diskData[masterIndexOffset + 256 + i]
                    let indexBlock = Int(indexBlockPtrLo) | (Int(indexBlockPtrHi) << 8)
                    
                    if indexBlock == 0 {
                        print("      Index block \(i): NULL (stopping)")
                        break
                    }
                    
                    indexBlockCount += 1
                    print("      Index block \(i): block#\(indexBlock)")
                    
                    // Each index block has 256 data block pointers
                    let indexBlockOffset = indexBlock * self.BLOCK_SIZE
                    var dataBlocksInThisIndex = 0
                    
                    for j in 0..<256 {
                        if remainingSize <= 0 { break }
                        
                        let dataPtrLo = diskData[indexBlockOffset + j]
                        let dataPtrHi = diskData[indexBlockOffset + 256 + j]
                        let dataBlock = Int(dataPtrLo) | (Int(dataPtrHi) << 8)
                        
                        if dataBlock == 0 { break }
                        
                        dataBlocksInThisIndex += 1
                        let blockOffset = dataBlock * self.BLOCK_SIZE
                        let bytesToRead = min(self.BLOCK_SIZE, remainingSize)
                        fileData.append(diskData[blockOffset..<(blockOffset + bytesToRead)])
                        remainingSize -= bytesToRead
                    }
                    
                    print("         → Read \(dataBlocksInThisIndex) data blocks from this index")
                }
                
                print("   📊 Total index blocks processed: \(indexBlockCount)")
                print("   📊 Bytes extracted: \(fileData.count) / \(fileSize)")
            }
            
            print("   ✅ Extracted \(fileData.count) bytes")
            
            DispatchQueue.main.async {
                completion(true, fileData)
            }
        }
    }
    
    // MARK: - Check File Exists
    
    /// Checks if a file with the given name already exists in the volume directory
    private func fileExists(_ diskData: NSMutableData, fileName: String) -> Bool {
        return findFileEntry(Data(referencing: diskData), fileName: fileName) != nil
    }
    
    // MARK: - Find File Entry
    
    private func findFileEntry(_ diskData: Data, fileName: String, dirBlock: Int? = nil) -> (block: Int, offset: Int)? {
        let searchName = fileName.uppercased()
        
        if let specificDir = dirBlock {
            // Search only in specified directory (for path navigation)
            return searchDirectoryOnly(diskData, directoryBlock: specificDir, fileName: searchName)
        } else {
            // Start search from volume directory (recursive)
            return searchDirectory(diskData, directoryBlock: VOLUME_DIR_BLOCK, fileName: searchName)
        }
    }
    
    /// Searches ONLY in the specified directory (non-recursive)
    private func searchDirectoryOnly(_ diskData: Data, directoryBlock: Int, fileName: String) -> (block: Int, offset: Int)? {
        var currentBlock = directoryBlock
        var entryIndex = (directoryBlock == VOLUME_DIR_BLOCK) ? 1 : 0  // Skip header in volume dir
        
        // Search this directory only
        while currentBlock != 0 {
            let blockOffset = currentBlock * BLOCK_SIZE
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = blockOffset + 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = diskData[entryOffset] >> 4
                
                if storageType != 0 {
                    let nameLen = Int(diskData[entryOffset] & 0x0F)
                    var entryName = ""
                    for i in 0..<nameLen {
                        let char = diskData[entryOffset + 1 + i] & 0x7F
                        entryName.append(Character(UnicodeScalar(char)))
                    }
                    
                    // Found it!
                    if entryName == fileName {
                        return (currentBlock, entryOffset)
                    }
                }
                
                entryIndex += 1
            }
            
            let nextBlockLo = diskData[blockOffset + 2]
            let nextBlockHi = diskData[blockOffset + 3]
            currentBlock = Int(nextBlockLo) | (Int(nextBlockHi) << 8)
            entryIndex = 0
        }
        
        // Not found in this directory
        return nil
    }
    
    private func searchDirectory(_ diskData: Data, directoryBlock: Int, fileName: String) -> (block: Int, offset: Int)? {
        var currentBlock = directoryBlock
        var entryIndex = (directoryBlock == VOLUME_DIR_BLOCK) ? 1 : 0  // Skip header in volume dir
        var subdirectories: [(block: Int, name: String)] = []
        
        // Search this directory
        while currentBlock != 0 {
            let blockOffset = currentBlock * BLOCK_SIZE
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = blockOffset + 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = diskData[entryOffset] >> 4
                
                if storageType != 0 {
                    let nameLen = Int(diskData[entryOffset] & 0x0F)
                    var entryName = ""
                    for i in 0..<nameLen {
                        let char = diskData[entryOffset + 1 + i] & 0x7F
                        entryName.append(Character(UnicodeScalar(char)))
                    }
                    
                    // Found it!
                    if entryName == fileName {
                        return (currentBlock, entryOffset)
                    }
                    
                    // If it's a directory (storage type 0xD), remember it for later search
                    if storageType == 0xD {
                        let keyBlockLo = diskData[entryOffset + 0x11]
                        let keyBlockHi = diskData[entryOffset + 0x12]
                        let keyBlock = Int(keyBlockLo) | (Int(keyBlockHi) << 8)
                        subdirectories.append((block: keyBlock, name: entryName))
                    }
                }
                
                entryIndex += 1
            }
            
            let nextBlockLo = diskData[blockOffset + 2]
            let nextBlockHi = diskData[blockOffset + 3]
            currentBlock = Int(nextBlockLo) | (Int(nextBlockHi) << 8)
            entryIndex = 0
        }
        
        // Not found in this directory - search subdirectories recursively
        for subdir in subdirectories {
            if let result = searchDirectory(diskData, directoryBlock: subdir.block, fileName: fileName) {
                return result
            }
        }
        
        return nil
    }
    
    // MARK: - Create Disk Image
    
    func createDiskImage(at path: URL, volumeName: String, sizeString: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let totalBlocks: Int
                if sizeString.uppercased().contains("MB") {
                    let mb = Int(sizeString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 32
                    let calculatedBlocks = (mb * 1024 * 1024) / self.BLOCK_SIZE
                    totalBlocks = min(calculatedBlocks, 65535)  // ProDOS maximum!
                } else if sizeString.uppercased().contains("KB") {
                    let kb = Int(sizeString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 800
                    let calculatedBlocks = (kb * 1024) / self.BLOCK_SIZE
                    totalBlocks = min(calculatedBlocks, 65535)  // ProDOS maximum!
                } else {
                    totalBlocks = 65535
                }
                
                print("📝 Creating ProDOS disk image:")
                print("   Path: \(path.path)")
                print("   Volume: \(volumeName)")
                print("   Blocks: \(totalBlocks)")
                
                let diskData = NSMutableData(length: totalBlocks * self.BLOCK_SIZE)!
                
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
    
    /// Creates ProDOS boot blocks (blocks 0 and 1) - required for emulators to boot the disk
    private func createBootBlocks(_ diskData: NSMutableData) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        
        // ProDOS boot loader code (1024 bytes = 2 blocks)
        // This is the standard ProDOS boot loader that emulatorsexpect
        let bootCode: [UInt8] = [
            0x01, 0x38, 0xB0, 0x03, 0x4C, 0x32, 0xA1, 0x86, 0x43, 0xC9, 0x03, 0x08, 0x8A, 0x29, 0x70, 0x4A,
            0x4A, 0x4A, 0x4A, 0x09, 0xC0, 0x85, 0x49, 0xA0, 0xFF, 0x84, 0x48, 0x28, 0xC8, 0xB1, 0x48, 0xD0,
            0x3A, 0xB0, 0x0E, 0xA9, 0x03, 0x8D, 0x00, 0x08, 0xE6, 0x3D, 0xA5, 0x49, 0x48, 0xA9, 0x5B, 0x48,
            0x60, 0x85, 0x40, 0x85, 0x48, 0xA0, 0x63, 0xB1, 0x48, 0x99, 0x94, 0x09, 0xC8, 0xC0, 0xEB, 0xD0,
            0xF6, 0xA2, 0x06, 0xBC, 0x1D, 0x09, 0xBD, 0x24, 0x09, 0x99, 0xF2, 0x09, 0xBD, 0x2B, 0x09, 0x9D,
            0x7F, 0x0A, 0xCA, 0x10, 0xEE, 0xA9, 0x09, 0x85, 0x49, 0xA9, 0x86, 0xA0, 0x00, 0xC9, 0xF9, 0xB0,
            0x2F, 0x85, 0x48, 0x84, 0x60, 0x84, 0x4A, 0x84, 0x4C, 0x84, 0x4E, 0x84, 0x47, 0xC8, 0x84, 0x42,
            0xC8, 0x84, 0x46, 0xA9, 0x0C, 0x85, 0x61, 0x85, 0x4B, 0x20, 0x12, 0x09, 0xB0, 0x68, 0xE6, 0x61,
            0xE6, 0x61, 0xE6, 0x46, 0xA5, 0x46, 0xC9, 0x06, 0x90, 0xEF, 0xAD, 0x00, 0x0C, 0x0D, 0x01, 0x0C,
            0xD0, 0x6D, 0xA9, 0x04, 0xD0, 0x02, 0xA5, 0x4A, 0x18, 0x6D, 0x23, 0x0C, 0xA8, 0x90, 0x0D, 0xE6,
            0x4B, 0xA5, 0x4B, 0x4A, 0xB0, 0x06, 0xC9, 0x0A, 0xF0, 0x55, 0xA0, 0x04, 0x84, 0x4A, 0xAD, 0x02,
            0x09, 0x29, 0x0F, 0xA8, 0xB1, 0x4A, 0xD9, 0x02, 0x09, 0xD0, 0xDB, 0x88, 0x10, 0xF6, 0x29, 0xF0,
            0xC9, 0x20, 0xD0, 0x3B, 0xA0, 0x10, 0xB1, 0x4A, 0xC9, 0xFF, 0xD0, 0x33, 0xC8, 0xB1, 0x4A, 0x85,
            0x46, 0xC8, 0xB1, 0x4A, 0x85, 0x47, 0xA9, 0x00, 0x85, 0x4A, 0xA0, 0x1E, 0x84, 0x4B, 0x84, 0x61,
            0xC8, 0x84, 0x4D, 0x20, 0x12, 0x09, 0xB0, 0x17, 0xE6, 0x61, 0xE6, 0x61, 0xA4, 0x4E, 0xE6, 0x4E,
            0xB1, 0x4A, 0x85, 0x46, 0xB1, 0x4C, 0x85, 0x47, 0x11, 0x4A, 0xD0, 0xE7, 0x4C, 0x00, 0x20, 0x4C,
            0x3F, 0x09, 0x26, 0x50, 0x52, 0x4F, 0x44, 0x4F, 0x53, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
            0x20, 0x20, 0xA5, 0x60, 0x85, 0x44, 0xA5, 0x61, 0x85, 0x45, 0x6C, 0x48, 0x00, 0x08, 0x1E, 0x24,
            0x3F, 0x45, 0x47, 0x76, 0xF4, 0xD7, 0xD1, 0xB6, 0x4B, 0xB4, 0xAC, 0xA6, 0x2B, 0x18, 0x60, 0x4C,
            0xBC, 0x09, 0xA9, 0x9F, 0x48, 0xA9, 0xFF, 0x48, 0xA9, 0x01, 0xA2, 0x00, 0x4C, 0x79, 0xF4, 0x20,
            0x58, 0xFC, 0xA0, 0x1C, 0xB9, 0x50, 0x09, 0x99, 0xAE, 0x05, 0x88, 0x10, 0xF7, 0x4C, 0x4D, 0x09,
            0xAA, 0xAA, 0xAA, 0xA0, 0xD5, 0xCE, 0xC1, 0xC2, 0xCC, 0xC5, 0xA0, 0xD4, 0xCF, 0xA0, 0xCC, 0xCF,
            0xC1, 0xC4, 0xA0, 0xD0, 0xD2, 0xCF, 0xC4, 0xCF, 0xD3, 0xA0, 0xAA, 0xAA, 0xAA, 0xA5, 0x53, 0x29,
            0x03, 0x2A, 0x05, 0x2B, 0xAA, 0xBD, 0x80, 0xC0, 0xA9, 0x2C, 0xA2, 0x11, 0xCA, 0xD0, 0xFD, 0xE9,
            0x01, 0xD0, 0xF7, 0xA6, 0x2B, 0x60, 0xA5, 0x46, 0x29, 0x07, 0xC9, 0x04, 0x29, 0x03, 0x08, 0x0A,
            0x28, 0x2A, 0x85, 0x3D, 0xA5, 0x47, 0x4A, 0xA5, 0x46, 0x6A, 0x4A, 0x4A, 0x85, 0x41, 0x0A, 0x85,
            0x51, 0xA5, 0x45, 0x85, 0x27, 0xA6, 0x2B, 0xBD, 0x89, 0xC0, 0x20, 0xBC, 0x09, 0xE6, 0x27, 0xE6,
            0x3D, 0xE6, 0x3D, 0xB0, 0x03, 0x20, 0xBC, 0x09, 0xBC, 0x88, 0xC0, 0x60, 0xA5, 0x40, 0x0A, 0x85,
            0x53, 0xA9, 0x00, 0x85, 0x54, 0xA5, 0x53, 0x85, 0x50, 0x38, 0xE5, 0x51, 0xF0, 0x14, 0xB0, 0x04,
            0xE6, 0x53, 0x90, 0x02, 0xC6, 0x53, 0x38, 0x20, 0x6D, 0x09, 0xA5, 0x50, 0x18, 0x20, 0x6F, 0x09,
            0xD0, 0xE3, 0xA0, 0x7F, 0x84, 0x52, 0x08, 0x28, 0x38, 0xC6, 0x52, 0xF0, 0xCE, 0x18, 0x08, 0x88,
            0xF0, 0xF5, 0xBD, 0x8C, 0xC0, 0x10, 0xFB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x4C, 0x6E, 0xA0, 0x53, 0x4F, 0x53, 0x20, 0x42, 0x4F, 0x4F, 0x54, 0x20, 0x20, 0x31, 0x2E, 0x31,
            0x20, 0x0A, 0x53, 0x4F, 0x53, 0x2E, 0x4B, 0x45, 0x52, 0x4E, 0x45, 0x4C, 0x20, 0x20, 0x20, 0x20,
            0x20, 0x53, 0x4F, 0x53, 0x20, 0x4B, 0x52, 0x4E, 0x4C, 0x49, 0x2F, 0x4F, 0x20, 0x45, 0x52, 0x52,
            0x4F, 0x52, 0x08, 0x00, 0x46, 0x49, 0x4C, 0x45, 0x20, 0x27, 0x53, 0x4F, 0x53, 0x2E, 0x4B, 0x45,
            0x52, 0x4E, 0x45, 0x4C, 0x27, 0x20, 0x4E, 0x4F, 0x54, 0x20, 0x46, 0x4F, 0x55, 0x4E, 0x44, 0x25,
            0x00, 0x49, 0x4E, 0x56, 0x41, 0x4C, 0x49, 0x44, 0x20, 0x4B, 0x45, 0x52, 0x4E, 0x45, 0x4C, 0x20,
            0x46, 0x49, 0x4C, 0x45, 0x3A, 0x00, 0x00, 0x0C, 0x00, 0x1E, 0x0E, 0x1E, 0x04, 0xA4, 0x78, 0xD8,
            0xA9, 0x77, 0x8D, 0xDF, 0xFF, 0xA2, 0xFB, 0x9A, 0x2C, 0x10, 0xC0, 0xA9, 0x40, 0x8D, 0xCA, 0xFF,
            0xA9, 0x07, 0x8D, 0xEF, 0xFF, 0xA2, 0x00, 0xCE, 0xEF, 0xFF, 0x8E, 0x00, 0x20, 0xAD, 0x00, 0x20,
            0xD0, 0xF5, 0xA9, 0x01, 0x85, 0xE0, 0xA9, 0x00, 0x85, 0xE1, 0xA9, 0x00, 0x85, 0x85, 0xA9, 0xA2,
            0x85, 0x86, 0x20, 0xBE, 0xA1, 0xE6, 0xE0, 0xA9, 0x00, 0x85, 0xE6, 0xE6, 0x86, 0xE6, 0x86, 0xE6,
            0xE6, 0x20, 0xBE, 0xA1, 0xA0, 0x02, 0xB1, 0x85, 0x85, 0xE0, 0xC8, 0xB1, 0x85, 0x85, 0xE1, 0xD0,
            0xEA, 0xA5, 0xE0, 0xD0, 0xE6, 0xAD, 0x6C, 0xA0, 0x85, 0xE2, 0xAD, 0x6D, 0xA0, 0x85, 0xE3, 0x18,
            0xA5, 0xE3, 0x69, 0x02, 0x85, 0xE5, 0x38, 0xA5, 0xE2, 0xED, 0x23, 0xA4, 0x85, 0xE4, 0xA5, 0xE5,
            0xE9, 0x00, 0x85, 0xE5, 0xA0, 0x00, 0xB1, 0xE2, 0x29, 0x0F, 0xCD, 0x11, 0xA0, 0xD0, 0x21, 0xA8,
            0xB1, 0xE2, 0xD9, 0x11, 0xA0, 0xD0, 0x19, 0x88, 0xD0, 0xF6, 0xA0, 0x00, 0xB1, 0xE2, 0x29, 0xF0,
            0xC9, 0x20, 0xF0, 0x3E, 0xC9, 0xF0, 0xF0, 0x08, 0xAE, 0x64, 0xA0, 0xA0, 0x13, 0x4C, 0xD4, 0xA1,
            0x18, 0xA5, 0xE2, 0x6D, 0x23, 0xA4, 0x85, 0xE2, 0xA5, 0xE3, 0x69, 0x00, 0x85, 0xE3, 0xA5, 0xE4,
            0xC5, 0xE2, 0xA5, 0xE5, 0xE5, 0xE3, 0xB0, 0xBC, 0x18, 0xA5, 0xE4, 0x6D, 0x23, 0xA4, 0x85, 0xE2,
            0xA5, 0xE5, 0x69, 0x00, 0x85, 0xE3, 0xC6, 0xE6, 0xD0, 0x95, 0xAE, 0x4F, 0xA0, 0xA0, 0x1B, 0x4C,
            0xD4, 0xA1, 0xA0, 0x11, 0xB1, 0xE2, 0x85, 0xE0, 0xC8, 0xB1, 0xE2, 0x85, 0xE1, 0xAD, 0x66, 0xA0,
            0x85, 0x85, 0xAD, 0x67, 0xA0, 0x85, 0x86, 0x20, 0xBE, 0xA1, 0xAD, 0x68, 0xA0, 0x85, 0x85, 0xAD,
            0x69, 0xA0, 0x85, 0x86, 0xAD, 0x00, 0x0C, 0x85, 0xE0, 0xAD, 0x00, 0x0D, 0x85, 0xE1, 0x20, 0xBE,
            0xA1, 0xA2, 0x07, 0xBD, 0x00, 0x1E, 0xDD, 0x21, 0xA0, 0xF0, 0x08, 0xAE, 0x64, 0xA0, 0xA0, 0x13,
            0x4C, 0xD4, 0xA1, 0xCA, 0x10, 0xED, 0xA9, 0x00, 0x85, 0xE7, 0xE6, 0xE7, 0xE6, 0x86, 0xE6, 0x86,
            0xA6, 0xE7, 0xBD, 0x00, 0x0C, 0x85, 0xE0, 0xBD, 0x00, 0x0D, 0x85, 0xE1, 0xA5, 0xE0, 0xD0, 0x04,
            0xA5, 0xE1, 0xF0, 0x06, 0x20, 0xBE, 0xA1, 0x4C, 0x8A, 0xA1, 0x18, 0xAD, 0x6A, 0xA0, 0x6D, 0x08,
            0x1E, 0x85, 0xE8, 0xAD, 0x6B, 0xA0, 0x6D, 0x09, 0x1E, 0x85, 0xE9, 0x6C, 0xE8, 0x00, 0xA9, 0x01,
            0x85, 0x87, 0xA5, 0xE0, 0xA6, 0xE1, 0x20, 0x79, 0xF4, 0xB0, 0x01, 0x60, 0xAE, 0x32, 0xA0, 0xA0,
            0x09, 0x4C, 0xD4, 0xA1, 0x84, 0xE7, 0x38, 0xA9, 0x28, 0xE5, 0xE7, 0x4A, 0x18, 0x65, 0xE7, 0xA8,
            0xBD, 0x29, 0xA0, 0x99, 0xA7, 0x05, 0xCA, 0x88, 0xC6, 0xE7, 0xD0, 0xF4, 0xAD, 0x40, 0xC0, 0x4C,
            0xEF, 0xA1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        
        // Copy boot code to blocks 0 and 1
        for i in 0..<bootCode.count {
            bytes[i] = bootCode[i]
        }
        
        print("   🚀 Created ProDOS boot blocks")
    }
    
    // MARK: - Create Volume Directory
    
    private func createVolumeDirectory(_ diskData: NSMutableData, volumeName: String, totalBlocks: Int) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let blockOffset = VOLUME_DIR_BLOCK * BLOCK_SIZE
        
        var nameBytes = [UInt8](repeating: 0x00, count: 15)  // Pad with 0x00, not 0xA0
        let nameData = volumeName.uppercased().data(using: .ascii) ?? Data()
        let nameLen = min(nameData.count, 15)
        for i in 0..<nameLen {
            nameBytes[i] = nameData[i]  // Plain ASCII - NO high bit for volume header!
        }
        
        // Volume directory header structure
        bytes[blockOffset + 0] = 0x00  // Previous block (LSB)
        bytes[blockOffset + 1] = 0x00  // Previous block (MSB)
        bytes[blockOffset + 2] = 0x03  // Next block (LSB) - points to block 3
        bytes[blockOffset + 3] = 0x00  // Next block (MSB)
        
        // Storage type ($F = volume header) and name length
        bytes[blockOffset + 4] = 0xF0 | UInt8(nameLen)
        
        // Volume name (15 bytes with high bit set)
        for i in 0..<15 {
            bytes[blockOffset + 5 + i] = nameBytes[i]
        }
        
        // Reserved bytes (8 bytes)
        for i in 0..<8 {
            bytes[blockOffset + 0x14 + i] = 0x00
        }
        
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        
        let year = (components.year ?? 2024) - 1900
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let dateWord = (year << 9) | (month << 5) | day
        bytes[blockOffset + 0x1C] = UInt8(dateWord & 0xFF)
        bytes[blockOffset + 0x1D] = UInt8((dateWord >> 8) & 0xFF)
        bytes[blockOffset + 0x1E] = UInt8(hour & 0x1F)
        bytes[blockOffset + 0x1F] = UInt8(minute & 0x3F)
        
        bytes[blockOffset + 0x20] = 0x00  // Version
        bytes[blockOffset + 0x21] = 0x00  // Min version
        bytes[blockOffset + 0x22] = 0xC3  // Access (read+write+destroy+rename)
        bytes[blockOffset + 0x23] = 0x27  // Entry length
        bytes[blockOffset + 0x24] = 0x0D  // Entries per block
        bytes[blockOffset + 0x25] = 0x00  // File count (LSB) - will be incremented
        bytes[blockOffset + 0x26] = 0x00  // File count (MSB)
        bytes[blockOffset + 0x27] = 0x06  // Bitmap pointer (LSB) - block 6
        bytes[blockOffset + 0x28] = 0x00  // Bitmap pointer (MSB)
        bytes[blockOffset + 0x29] = UInt8(totalBlocks & 0xFF)
        bytes[blockOffset + 0x2A] = UInt8((totalBlocks >> 8) & 0xFF)
        
        // Initialize directory blocks 3, 4, 5 (chain of 4 total blocks for proper ProDOS)
        // ProDOS standard: 4 directory blocks for volumes, allowing 51 file entries total
        
        // Block 3
        let block3Offset = 3 * BLOCK_SIZE
        bytes[block3Offset + 0] = 0x02  // Previous block = 2
        bytes[block3Offset + 1] = 0x00
        bytes[block3Offset + 2] = 0x04  // Next block = 4
        bytes[block3Offset + 3] = 0x00
        
        // Block 4
        let block4Offset = 4 * BLOCK_SIZE
        bytes[block4Offset + 0] = 0x03  // Previous block = 3
        bytes[block4Offset + 1] = 0x00
        bytes[block4Offset + 2] = 0x05  // Next block = 5
        bytes[block4Offset + 3] = 0x00
        
        // Block 5
        let block5Offset = 5 * BLOCK_SIZE
        bytes[block5Offset + 0] = 0x04  // Previous block = 4
        bytes[block5Offset + 1] = 0x00
        bytes[block5Offset + 2] = 0x00  // Next block = 0 (end of chain)
        bytes[block5Offset + 3] = 0x00
        
        print("   📂 Created volume directory (4 blocks: 2→3→4→5)")
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
                
                print("🗑️ Deleting file from ProDOS image:")
                print("   File: \(fileName)")
                
                // Find the file entry
                guard let (_, entryOffset) = self.findFileEntry(Data(referencing: diskData), fileName: fileName) else {
                    DispatchQueue.main.async {
                        completion(false, "File not found")
                    }
                    return
                }
                
                let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
                
                // Get file info before deleting
                let storageType = bytes[entryOffset] >> 4
                let keyBlockLo = bytes[entryOffset + 0x11]
                let keyBlockHi = bytes[entryOffset + 0x12]
                let keyBlock = Int(keyBlockLo) | (Int(keyBlockHi) << 8)
                let blocksUsedLo = bytes[entryOffset + 0x13]
                let blocksUsedHi = bytes[entryOffset + 0x14]
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
                    let indexOffset = keyBlock * self.BLOCK_SIZE
                    
                    // Free data blocks
                    for i in 0..<256 {
                        let ptrLo = bytes[indexOffset + i]
                        let ptrHi = bytes[indexOffset + 256 + i]
                        let dataBlock = Int(ptrLo) | (Int(ptrHi) << 8)
                        if dataBlock != 0 {
                            blocksToFree.append(dataBlock)
                        }
                    }
                    
                    // Free index block
                    blocksToFree.append(keyBlock)
                } else if storageType == 3 {
                    // Tree - master index + index blocks + data blocks
                    let masterOffset = keyBlock * self.BLOCK_SIZE
                    
                    for i in 0..<256 {
                        let indexPtrLo = bytes[masterOffset + i]
                        let indexPtrHi = bytes[masterOffset + 256 + i]
                        let indexBlock = Int(indexPtrLo) | (Int(indexPtrHi) << 8)
                        if indexBlock == 0 { continue }
                        
                        let indexOffset = indexBlock * self.BLOCK_SIZE
                        
                        // Free data blocks
                        for j in 0..<256 {
                            let dataPtrLo = bytes[indexOffset + j]
                            let dataPtrHi = bytes[indexOffset + 256 + j]
                            let dataBlock = Int(dataPtrLo) | (Int(dataPtrHi) << 8)
                            if dataBlock != 0 {
                                blocksToFree.append(dataBlock)
                            }
                        }
                        
                        // Free index block
                        blocksToFree.append(indexBlock)
                    }
                    
                    // Free master index block
                    blocksToFree.append(keyBlock)
                } else if storageType == 0xD {
                    // Subdirectory - just the header block (like seedling)
                    // Subdirectories should be empty before deletion
                    blocksToFree.append(keyBlock)
                    print("   📂 Deleting subdirectory (1 block)")
                }
                
                print("   🔓 Freeing \(blocksToFree.count) blocks")
                
                // Mark blocks as free in bitmap
                self.freeBlocks(diskData, blocks: blocksToFree)
                
                // Clear directory entry (mark as deleted)
                memset(bytes + entryOffset, 0, self.ENTRY_LENGTH)
                
                // Decrement file count
                self.decrementFileCount(diskData)
                
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
    
    private func freeBlocks(_ diskData: NSMutableData, blocks: [Int]) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let bitmapStartBlock = 6
        let bitmapOffset = bitmapStartBlock * BLOCK_SIZE
        
        for block in blocks {
            let byteIndex = block / 8
            let bitPosition = 7 - (block % 8)
            bytes[bitmapOffset + byteIndex] |= (1 << bitPosition)  // Set bit to 1 = free
        }
    }
    
    // MARK: - Decrement File Count
    
    private func decrementFileCount(_ diskData: NSMutableData) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let volHeaderOffset = VOLUME_DIR_BLOCK * BLOCK_SIZE + 4
        let fileCountOffset = volHeaderOffset + 0x25
        
        let currentCountLo = Int(bytes[fileCountOffset])
        let currentCountHi = Int(bytes[fileCountOffset + 1])
        var fileCount = currentCountLo | (currentCountHi << 8)
        
        fileCount = max(0, fileCount - 1)
        
        bytes[fileCountOffset] = UInt8(fileCount & 0xFF)
        bytes[fileCountOffset + 1] = UInt8((fileCount >> 8) & 0xFF)
        
        print("   📊 Updated file count: \(fileCount)")
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
