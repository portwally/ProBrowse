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
    
    // MARK: - Add File to Disk Image
    
    /// Adds a file to a ProDOS disk image
    func addFile(diskImagePath: URL, fileName: String, fileData: Data, fileType: UInt8, auxType: UInt16, completion: @escaping (Bool, String) -> Void) {
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Load entire disk image into memory
                guard var diskData = try? Data(contentsOf: diskImagePath) else {
                    DispatchQueue.main.async {
                        completion(false, "Could not read disk image")
                    }
                    return
                }
                
                print("📝 Adding file to ProDOS image:")
                print("   File: \(fileName)")
                print("   Size: \(fileData.count) bytes")
                print("   Type: $\(String(format: "%02X", fileType))")
                print("   Image: \(diskImagePath.lastPathComponent)")
                
                // 1. Find free directory entry
                guard let (dirBlock, entryOffset) = self.findFreeDirectoryEntry(&diskData) else {
                    DispatchQueue.main.async {
                        completion(false, "No free directory entries")
                    }
                    return
                }
                
                print("   📂 Free entry at block \(dirBlock), offset \(entryOffset)")
                
                // 2. Allocate blocks for file data
                let blocksNeeded = (fileData.count + self.BLOCK_SIZE - 1) / self.BLOCK_SIZE
                guard let dataBlocks = self.allocateBlocks(&diskData, count: blocksNeeded) else {
                    DispatchQueue.main.async {
                        completion(false, "Not enough free blocks (need \(blocksNeeded))")
                    }
                    return
                }
                
                print("   💾 Allocated \(blocksNeeded) blocks: \(dataBlocks)")
                
                // 3. Write file data to allocated blocks
                self.writeFileData(&diskData, fileData: fileData, blocks: dataBlocks)
                
                // 4. Create directory entry
                self.createDirectoryEntry(&diskData, dirBlock: dirBlock, entryOffset: entryOffset, 
                                        fileName: fileName, fileType: fileType, auxType: auxType,
                                        blocks: dataBlocks, fileSize: fileData.count)
                
                // 5. Update file count in volume header
                self.incrementFileCount(&diskData)
                
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
    
    // MARK: - Find Free Directory Entry
    
    private func findFreeDirectoryEntry(_ diskData: inout Data) -> (block: Int, offset: Int)? {
        // Start at volume directory block 2
        var currentBlock = VOLUME_DIR_BLOCK
        
        // Volume header is in first entry of block 2
        // Entries start at offset 0x27 (after header)
        var entryIndex = 1  // Skip header entry
        
        while currentBlock != 0 {
            let blockOffset = currentBlock * BLOCK_SIZE
            
            // Check entries in this block
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = blockOffset + 4 + (entryIndex * ENTRY_LENGTH)
                
                // Check storage_type (high nibble of first byte)
                let storageType = diskData[entryOffset] >> 4
                
                if storageType == 0 {
                    // Found free entry!
                    return (currentBlock, entryOffset)
                }
                
                entryIndex += 1
            }
            
            // Move to next directory block (pointer at +0x02)
            let nextBlockLo = diskData[blockOffset + 2]
            let nextBlockHi = diskData[blockOffset + 3]
            currentBlock = Int(nextBlockLo) | (Int(nextBlockHi) << 8)
            entryIndex = 0  // Start from first entry in next block
        }
        
        return nil
    }
    
    // MARK: - Allocate Blocks
    
    private func allocateBlocks(_ diskData: inout Data, count: Int) -> [Int]? {
        // Read volume bitmap starting at block 6
        var allocatedBlocks: [Int] = []
        
        // Simple linear search for free blocks
        // Start searching after boot blocks (0-1), volume dir (2-5), and bitmap blocks (6+)
        let startBlock = 24  // Start after system area
        
        // Get total blocks from volume header
        let volHeaderOffset = VOLUME_DIR_BLOCK * BLOCK_SIZE
        let totalBlocksLo = diskData[volHeaderOffset + 0x29]
        let totalBlocksHi = diskData[volHeaderOffset + 0x2A]
        let totalBlocks = Int(totalBlocksLo) | (Int(totalBlocksHi) << 8)
        
        print("   🔍 Searching for \(count) free blocks (total: \(totalBlocks))")
        
        // Find free blocks by checking bitmap
        let bitmapStartBlock = 6
        let bitmapBlockCount = (totalBlocks + (BLOCK_SIZE * 8) - 1) / (BLOCK_SIZE * 8)
        
        for block in startBlock..<totalBlocks {
            if allocatedBlocks.count >= count {
                break
            }
            
            // Check if block is free in bitmap
            let bitIndex = block
            let byteIndex = bitIndex / 8
            let bitPosition = 7 - (bitIndex % 8)
            
            let bitmapBlock = bitmapStartBlock + (byteIndex / BLOCK_SIZE)
            let bitmapByteOffset = byteIndex % BLOCK_SIZE
            let bitmapOffset = bitmapBlock * BLOCK_SIZE + bitmapByteOffset
            
            let bitmapByte = diskData[bitmapOffset]
            let isFree = (bitmapByte & (1 << bitPosition)) != 0
            
            if isFree {
                allocatedBlocks.append(block)
                
                // Mark block as used in bitmap
                diskData[bitmapOffset] = bitmapByte & ~(1 << bitPosition)
            }
        }
        
        if allocatedBlocks.count < count {
            return nil  // Not enough free blocks
        }
        
        return allocatedBlocks
    }
    
    // MARK: - Write File Data
    
    private func writeFileData(_ diskData: inout Data, fileData: Data, blocks: [Int]) {
        var dataOffset = 0
        
        for block in blocks {
            let blockOffset = block * BLOCK_SIZE
            let bytesToWrite = min(BLOCK_SIZE, fileData.count - dataOffset)
            
            let chunk = fileData[dataOffset..<(dataOffset + bytesToWrite)]
            diskData.replaceSubrange(blockOffset..<(blockOffset + bytesToWrite), with: chunk)
            
            // Pad rest of block with zeros if needed
            if bytesToWrite < BLOCK_SIZE {
                let padding = Data(repeating: 0, count: BLOCK_SIZE - bytesToWrite)
                diskData.replaceSubrange((blockOffset + bytesToWrite)..<(blockOffset + BLOCK_SIZE), with: padding)
            }
            
            dataOffset += bytesToWrite
        }
    }
    
    // MARK: - Create Directory Entry
    
    private func createDirectoryEntry(_ diskData: inout Data, dirBlock: Int, entryOffset: Int,
                                     fileName: String, fileType: UInt8, auxType: UInt16,
                                     blocks: [Int], fileSize: Int) {
        
        // Storage type: 1 = seedling (1 block), 2 = sapling (2-256 blocks), 3 = tree (257+ blocks)
        let storageType: UInt8
        if blocks.count == 1 {
            storageType = 1  // Seedling
        } else if blocks.count <= 256 {
            storageType = 2  // Sapling
        } else {
            storageType = 3  // Tree
        }
        
        // Prepare file name (max 15 chars, space-padded, high-ASCII)
        var nameBytes = [UInt8](repeating: 0xA0, count: 15)  // 0xA0 = space with high bit set
        let nameData = fileName.uppercased().data(using: .ascii) ?? Data()
        let nameLen = min(nameData.count, 15)
        for i in 0..<nameLen {
            nameBytes[i] = nameData[i] | 0x80  // Set high bit
        }
        
        // Build directory entry (39 bytes)
        var entry = Data(count: ENTRY_LENGTH)
        
        // +0x00: Storage type and name length
        entry[0] = (storageType << 4) | UInt8(nameLen)
        
        // +0x01-0x0F: File name (15 bytes)
        entry.replaceSubrange(1..<16, with: nameBytes)
        
        // +0x10: File type
        entry[0x10] = fileType
        
        // +0x11-0x12: Key pointer (first block for seedling, index block for sapling/tree)
        let keyBlock = blocks[0]
        entry[0x11] = UInt8(keyBlock & 0xFF)
        entry[0x12] = UInt8((keyBlock >> 8) & 0xFF)
        
        // +0x13-0x14: Blocks used
        entry[0x13] = UInt8(blocks.count & 0xFF)
        entry[0x14] = UInt8((blocks.count >> 8) & 0xFF)
        
        // +0x15-0x17: EOF (file size, 3 bytes little-endian)
        entry[0x15] = UInt8(fileSize & 0xFF)
        entry[0x16] = UInt8((fileSize >> 8) & 0xFF)
        entry[0x17] = UInt8((fileSize >> 16) & 0xFF)
        
        // +0x18-0x1B: Creation date/time (ProDOS format)
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        
        let year = (components.year ?? 2024) - 1900
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        // ProDOS date format: YYYYYYYM MMMDDDDD
        let dateWord = (year << 9) | (month << 5) | day
        entry[0x18] = UInt8(dateWord & 0xFF)
        entry[0x19] = UInt8((dateWord >> 8) & 0xFF)
        
        // ProDOS time format: 000HHHHH 00MMMMMM
        entry[0x1A] = UInt8(hour & 0x1F)
        entry[0x1B] = UInt8(minute & 0x3F)
        
        // +0x1C: Version (0x00)
        entry[0x1C] = 0x00
        
        // +0x1D: Min version (0x00)
        entry[0x1D] = 0x00
        
        // +0x1E: Access (0xE3 = read/write/delete/rename)
        entry[0x1E] = 0xE3
        
        // +0x1F-0x20: Aux type (2 bytes little-endian)
        entry[0x1F] = UInt8(auxType & 0xFF)
        entry[0x20] = UInt8((auxType >> 8) & 0xFF)
        
        // +0x21-0x24: Last modified date/time (same as creation)
        entry[0x21] = entry[0x18]
        entry[0x22] = entry[0x19]
        entry[0x23] = entry[0x1A]
        entry[0x24] = entry[0x1B]
        
        // +0x25-0x26: Header pointer (points to volume dir block, usually 2)
        entry[0x25] = UInt8(VOLUME_DIR_BLOCK & 0xFF)
        entry[0x26] = UInt8((VOLUME_DIR_BLOCK >> 8) & 0xFF)
        
        // Write entry to disk
        diskData.replaceSubrange(entryOffset..<(entryOffset + ENTRY_LENGTH), with: entry)
    }
    
    // MARK: - Update File Count
    
    private func incrementFileCount(_ diskData: inout Data) {
        let volHeaderOffset = VOLUME_DIR_BLOCK * BLOCK_SIZE
        let fileCountOffset = volHeaderOffset + 0x25
        
        let currentCountLo = diskData[fileCountOffset]
        let currentCountHi = diskData[fileCountOffset + 1]
        var fileCount = Int(currentCountLo) | (Int(currentCountHi) << 8)
        
        fileCount += 1
        
        diskData[fileCountOffset] = UInt8(fileCount & 0xFF)
        diskData[fileCountOffset + 1] = UInt8((fileCount >> 8) & 0xFF)
        
        print("   📊 Updated file count: \(fileCount)")
    }
    
    // MARK: - Extract File
    
    /// Extracts a file from ProDOS disk image
    func extractFile(diskImagePath: URL, fileName: String, completion: @escaping (Bool, Data?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let diskData = try? Data(contentsOf: diskImagePath) else {
                    DispatchQueue.main.async {
                        completion(false, nil)
                    }
                    return
                }
                
                print("📤 Extracting file from ProDOS image:")
                print("   File: \(fileName)")
                
                // Find file entry
                guard let (dirBlock, entryOffset) = self.findFileEntry(diskData, fileName: fileName) else {
                    print("   ❌ File not found")
                    DispatchQueue.main.async {
                        completion(false, nil)
                    }
                    return
                }
                
                // Read file metadata
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
                
                // Extract file data based on storage type
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
                        
                        let ptrLo = diskData[indexBlockOffset + i * 2]
                        let ptrHi = diskData[indexBlockOffset + i * 2 + 1]
                        let dataBlock = Int(ptrLo) | (Int(ptrHi) << 8)
                        
                        if dataBlock == 0 { break }
                        
                        let blockOffset = dataBlock * self.BLOCK_SIZE
                        let bytesToRead = min(self.BLOCK_SIZE, remainingSize)
                        fileData.append(diskData[blockOffset..<(blockOffset + bytesToRead)])
                        remainingSize -= bytesToRead
                    }
                }
                
                print("   ✅ Extracted \(fileData.count) bytes")
                
                DispatchQueue.main.async {
                    completion(true, fileData)
                }
                
            } catch {
                print("   ❌ Error: \(error)")
                DispatchQueue.main.async {
                    completion(false, nil)
                }
            }
        }
    }
    
    // MARK: - Find File Entry
    
    private func findFileEntry(_ diskData: Data, fileName: String) -> (block: Int, offset: Int)? {
        let searchName = fileName.uppercased()
        var currentBlock = VOLUME_DIR_BLOCK
        var entryIndex = 1  // Skip volume header
        
        while currentBlock != 0 {
            let blockOffset = currentBlock * BLOCK_SIZE
            
            while entryIndex < ENTRIES_PER_BLOCK {
                let entryOffset = blockOffset + 4 + (entryIndex * ENTRY_LENGTH)
                let storageType = diskData[entryOffset] >> 4
                
                if storageType != 0 {
                    // Read file name
                    let nameLen = Int(diskData[entryOffset] & 0x0F)
                    var entryName = ""
                    for i in 0..<nameLen {
                        let char = diskData[entryOffset + 1 + i] & 0x7F  // Clear high bit
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
}
