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
    
    // MARK: - Sanitize Filename
    
    /// Sanitizes a filename for ProDOS: removes invalid chars, max 15 chars, uppercase
    private func sanitizeProDOSFilename(_ filename: String) -> String {
        var name = filename.uppercased()
        
        // Remove file extension if present
        if let dotIndex = name.lastIndex(of: ".") {
            name = String(name[..<dotIndex])
        }
        
        // ProDOS allows: A-Z, 0-9, and period (.)
        // But period causes issues, so we remove it
        let validChars = CharacterSet.alphanumerics
        name = name.filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return validChars.contains(scalar)
        }
        
        // Max 15 characters
        if name.count > 15 {
            name = String(name.prefix(15))
        }
        
        // Ensure not empty
        if name.isEmpty {
            name = "UNNAMED"
        }
        
        return name
    }
    
    // MARK: - Add File to Disk Image
    
    /// Adds a file to a ProDOS disk image
    func addFile(diskImagePath: URL, fileName: String, fileData: Data, fileType: UInt8, auxType: UInt16, completion: @escaping (Bool, String) -> Void) {
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Sanitize filename for ProDOS (remove invalid chars, max 15 chars)
                var sanitizedName = self.sanitizeProDOSFilename(fileName)
                
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
                print("   Size: \(fileData.count) bytes")
                print("   Type: $\(String(format: "%02X", fileType))")
                print("   Image: \(diskImagePath.lastPathComponent)")
                
                // 1. Find free directory entry
                guard let (dirBlock, entryOffset) = self.findFreeDirectoryEntry(diskData) else {
                    DispatchQueue.main.async {
                        completion(false, "No free directory entries")
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
                
                // 4. For sapling/tree files, create index block
                var keyBlock = dataBlocks[0]  // Default for seedling
                var totalBlocks = dataBlocks.count
                
                if dataBlocks.count > 1 {
                    // Need an index block for sapling/tree files
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
                
                // 5. Update file count in volume header
                self.incrementFileCount(diskData)
                
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
    
    private func findFreeDirectoryEntry(_ diskData: NSMutableData) -> (block: Int, offset: Int)? {
        let bytes = diskData.bytes.assumingMemoryBound(to: UInt8.self)
        var currentBlock = VOLUME_DIR_BLOCK
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
        var allocatedBlocks: [Int] = []
        
        let startBlock = 24
        let volHeaderOffset = VOLUME_DIR_BLOCK * BLOCK_SIZE
        let totalBlocksLo = Int(bytes[volHeaderOffset + 0x29])
        let totalBlocksHi = Int(bytes[volHeaderOffset + 0x2A])
        let totalBlocks = totalBlocksLo | (totalBlocksHi << 8)
        
        print("   🔍 Searching for \(count) free blocks (total: \(totalBlocks))")
        
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
            let bitmapOffset = bitmapBlock * BLOCK_SIZE + bitmapByteOffset
            
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
        
        var nameBytes = [UInt8](repeating: 0xA0, count: 15)
        let nameData = fileName.uppercased().data(using: .ascii) ?? Data()
        let nameLen = min(nameData.count, 15)
        for i in 0..<nameLen {
            // ProDOS names need high bit set (0x80)
            nameBytes[i] = nameData[i] | 0x80
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
        
        entry[0x25] = UInt8(VOLUME_DIR_BLOCK & 0xFF)
        entry[0x26] = UInt8((VOLUME_DIR_BLOCK >> 8) & 0xFF)
        
        memcpy(bytes + entryOffset, entry, ENTRY_LENGTH)
    }
    
    // MARK: - Update File Count
    
    private func incrementFileCount(_ diskData: NSMutableData) {
        let bytes = diskData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let volHeaderOffset = VOLUME_DIR_BLOCK * BLOCK_SIZE
        let fileCountOffset = volHeaderOffset + 0x25
        
        let currentCountLo = Int(bytes[fileCountOffset])
        let currentCountHi = Int(bytes[fileCountOffset + 1])
        var fileCount = currentCountLo | (currentCountHi << 8)
        
        fileCount += 1
        
        bytes[fileCountOffset] = UInt8(fileCount & 0xFF)
        bytes[fileCountOffset + 1] = UInt8((fileCount >> 8) & 0xFF)
        
        print("   📊 Updated file count: \(fileCount)")
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
                for i in 0..<256 {
                    if remainingSize <= 0 { break }
                    
                    let indexBlockPtrLo = diskData[masterIndexOffset + i]
                    let indexBlockPtrHi = diskData[masterIndexOffset + 256 + i]
                    let indexBlock = Int(indexBlockPtrLo) | (Int(indexBlockPtrHi) << 8)
                    
                    if indexBlock == 0 { break }
                    
                    print("      Index block \(i): block#\(indexBlock)")
                    
                    // Each index block has 256 data block pointers
                    let indexBlockOffset = indexBlock * self.BLOCK_SIZE
                    
                    for j in 0..<256 {
                        if remainingSize <= 0 { break }
                        
                        let dataPtrLo = diskData[indexBlockOffset + j]
                        let dataPtrHi = diskData[indexBlockOffset + 256 + j]
                        let dataBlock = Int(dataPtrLo) | (Int(dataPtrHi) << 8)
                        
                        if dataBlock == 0 { break }
                        
                        let blockOffset = dataBlock * self.BLOCK_SIZE
                        let bytesToRead = min(self.BLOCK_SIZE, remainingSize)
                        fileData.append(diskData[blockOffset..<(blockOffset + bytesToRead)])
                        remainingSize -= bytesToRead
                    }
                }
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
    
    private func findFileEntry(_ diskData: Data, fileName: String) -> (block: Int, offset: Int)? {
        let searchName = fileName.uppercased()
        var currentBlock = VOLUME_DIR_BLOCK
        var entryIndex = 1
        
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
                    
                    if entryName == searchName {
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
        
        return nil
    }
    
    // MARK: - Create Disk Image
    
    func createDiskImage(at path: URL, volumeName: String, sizeString: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let totalBlocks: Int
                if sizeString.uppercased().contains("MB") {
                    let mb = Int(sizeString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 32
                    totalBlocks = (mb * 1024 * 1024) / self.BLOCK_SIZE
                } else if sizeString.uppercased().contains("KB") {
                    let kb = Int(sizeString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 800
                    totalBlocks = (kb * 1024) / self.BLOCK_SIZE
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
        bytes[blockOffset + 0x22] = 0x63  // Access (not 0xC3!)
        bytes[blockOffset + 0x23] = 0x27  // Entry length
        bytes[blockOffset + 0x24] = 0x0D
        bytes[blockOffset + 0x25] = 0
        bytes[blockOffset + 0x26] = 0
        bytes[blockOffset + 0x27] = 6
        bytes[blockOffset + 0x28] = 0
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
                guard let (dirBlock, entryOffset) = self.findFileEntry(Data(referencing: diskData), fileName: fileName) else {
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
