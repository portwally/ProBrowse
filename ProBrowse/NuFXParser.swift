//
//  NuFXParser.swift
//  ProBrowse
//
//  Native Swift parser for NuFX (ShrinkIt) archives (.sdk, .shk, .bxy)
//  Extracts disk images from compressed archives
//

import Foundation

class NuFXParser {
    
    // MARK: - Constants
    
    private static let NUFX_MASTER_ID: [UInt8] = [0x4E, 0xF5, 0x46, 0xE9, 0x6C, 0xE5]
    private static let NUFX_RECORD_ID: [UInt8] = [0x4E, 0xF5, 0x46, 0xD8]
    private static let FLOPPY_140K = 143360
    
    // Thread classes
    private static let THREAD_CLASS_DATA: UInt16 = 0x0002
    private static let THREAD_CLASS_FILENAME: UInt16 = 0x0003
    
    // Thread kinds
    private static let THREAD_KIND_DISK_IMAGE: UInt16 = 0x0001
    
    // Thread formats
    private static let THREAD_FORMAT_UNCOMPRESSED: UInt16 = 0x0000
    private static let THREAD_FORMAT_LZW2: UInt16 = 0x0003
    
    // MARK: - Public Interface
    
    /// Check if data appears to be a NuFX archive
    static func isNuFXArchive(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        for i in 0..<6 {
            if data[i] != NUFX_MASTER_ID[i] { return false }
        }
        return true
    }
    
    /// Check file extension for ShrinkIt formats
    static func isShrinkItExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return lower == "sdk" || lower == "shk" || lower == "bxy" || lower == "bny" || lower == "bqy"
    }
    
    /// Extract disk image from NuFX archive
    /// Returns the raw disk image data, or nil if extraction fails
    static func extractDiskImage(from url: URL) -> Data? {
        guard let archiveData = try? Data(contentsOf: url) else {
            print("❌ NuFX: Cannot read file")
            return nil
        }
        
        guard isNuFXArchive(archiveData) else {
            print("❌ NuFX: Invalid signature")
            return nil
        }
        
        // Try native extraction first
        if let result = extractDiskImageNative(from: archiveData) {
            return result
        }
        
        // Fall back to nulib2 command-line tool
        print("📦 NuFX: Trying nulib2 extraction...")
        return extractUsingNulib2(url: url)
    }
    
    // MARK: - Native Extraction
    
    private static func extractDiskImageNative(from data: Data) -> Data? {
        print("📦 NuFX: Parsing archive structure...")
        
        // Parse master header
        guard data.count >= 48 else { return nil }
        
        let totalRecords = readUInt32(data, offset: 8)
        print("   Records: \(totalRecords)")
        
        // Parse first record
        var offset = 48
        
        guard offset + 4 <= data.count,
              data[offset] == NUFX_RECORD_ID[0],
              data[offset + 1] == NUFX_RECORD_ID[1],
              data[offset + 2] == NUFX_RECORD_ID[2],
              data[offset + 3] == NUFX_RECORD_ID[3] else {
            print("❌ NuFX: Invalid record signature")
            return nil
        }
        
        let attribCount = readUInt16(data, offset: offset + 6)
        let totalThreads = readUInt32(data, offset: offset + 10)
        
        // Get filename length (at end of attributes)
        let fnLenOffset = offset + Int(attribCount) - 2
        let filenameLength = Int(readUInt16(data, offset: fnLenOffset))
        
        // Read filename
        let fnStart = offset + Int(attribCount)
        var filename = ""
        if filenameLength > 0 && fnStart + filenameLength <= data.count {
            let fnData = data.subdata(in: fnStart..<(fnStart + filenameLength))
            filename = String(data: fnData, encoding: .ascii) ?? ""
        }
        print("   Filename: \(filename)")
        
        // Parse threads
        let threadsStart = offset + Int(attribCount) + filenameLength
        var dataOffset = threadsStart + Int(totalThreads) * 16
        
        for i in 0..<totalThreads {
            let threadOffset = threadsStart + Int(i) * 16
            guard threadOffset + 16 <= data.count else { break }
            
            let threadClass = readUInt16(data, offset: threadOffset)
            let threadFormat = readUInt16(data, offset: threadOffset + 2)
            let threadKind = readUInt16(data, offset: threadOffset + 4)
            let threadEOF = readUInt32(data, offset: threadOffset + 8)
            let compThreadEOF = readUInt32(data, offset: threadOffset + 12)
            
            // Look for disk image thread
            if threadClass == THREAD_CLASS_DATA && threadKind == THREAD_KIND_DISK_IMAGE {
                print("   Found disk image thread (format=\(threadFormat), size=\(threadEOF), compressed=\(compThreadEOF))")
                
                let compressedData = data.subdata(in: dataOffset..<(dataOffset + Int(compThreadEOF)))
                
                switch threadFormat {
                case THREAD_FORMAT_UNCOMPRESSED:
                    print("   Format: Uncompressed")
                    return padToFloppySize(compressedData, expectedSize: Int(threadEOF))
                    
                case THREAD_FORMAT_LZW2:
                    print("   Format: LZW/2")
                    if let decompressed = decompressLZW2(compressedData, expectedSize: Int(threadEOF)) {
                        return padToFloppySize(decompressed, expectedSize: FLOPPY_140K)
                    }
                    return nil
                    
                default:
                    print("   ⚠️ Unsupported format: \(threadFormat)")
                    return nil
                }
            }
            
            dataOffset += Int(compThreadEOF)
        }
        
        print("❌ NuFX: No disk image thread found")
        return nil
    }
    
    // MARK: - LZW/2 Decompression
    
    private static func decompressLZW2(_ data: Data, expectedSize: Int) -> Data? {
        // NuFX LZW/2 format:
        // - 6-byte header: CRC(2) + params(4) 
        // - Then LZW stream with 9-12 bit variable codes
        // - Code 256 = CLEAR (reset dictionary)
        
        guard data.count > 6 else { return nil }
        
        // Skip 6-byte header
        var pos = 6
        var bitBuffer: UInt32 = 0
        var bitsAvailable = 0
        
        func readBits(_ count: Int) -> Int? {
            while bitsAvailable < count {
                guard pos < data.count else { return nil }
                bitBuffer |= UInt32(data[pos]) << bitsAvailable
                bitsAvailable += 8
                pos += 1
            }
            let result = Int(bitBuffer & ((1 << count) - 1))
            bitBuffer >>= count
            bitsAvailable -= count
            return result
        }
        
        var output = Data()
        output.reserveCapacity(expectedSize)
        
        // Dictionary: indices 0-255 are single bytes, 256 is CLEAR, 257+ are sequences
        var dictionary: [[UInt8]] = (0..<256).map { [UInt8($0)] }
        dictionary.append([])  // 256 = CLEAR placeholder
        
        let CLEAR_CODE = 256
        var nextCode = 257
        var codeBits = 9
        
        // Read first code
        guard let firstCode = readBits(codeBits), firstCode < 256 else {
            print("   ❌ Invalid first code")
            return nil
        }
        
        output.append(UInt8(firstCode))
        var prevSeq: [UInt8] = [UInt8(firstCode)]
        
        while output.count < expectedSize {
            // Read next code
            guard let code = readBits(codeBits) else { break }
            
            if code == CLEAR_CODE {
                // Reset dictionary
                dictionary = (0..<256).map { [UInt8($0)] }
                dictionary.append([])  // 256 = CLEAR
                nextCode = 257
                codeBits = 9
                
                // Read next literal
                guard let nextLiteral = readBits(codeBits), nextLiteral < 256 else { break }
                output.append(UInt8(nextLiteral))
                prevSeq = [UInt8(nextLiteral)]
                continue
            }
            
            var seq: [UInt8]
            
            if code < 256 {
                seq = [UInt8(code)]
            } else if code < dictionary.count {
                seq = dictionary[code]
            } else if code == nextCode {
                // KwKwK case
                seq = prevSeq + [prevSeq[0]]
            } else {
                print("   ❌ Invalid code \(code) at output \(output.count)")
                break
            }
            
            output.append(contentsOf: seq)
            
            // Add new dictionary entry
            if nextCode < 4096 {
                dictionary.append(prevSeq + [seq[0]])
                nextCode += 1
                
                // Grow code size when needed
                if nextCode >= (1 << codeBits) && codeBits < 12 {
                    codeBits += 1
                }
            }
            
            prevSeq = seq
        }
        
        print("   Decompressed: \(output.count) bytes")
        return output
    }
    
    // MARK: - nulib2 Fallback
    
    private static func extractUsingNulib2(url: URL) -> Data? {
        // Check if nulib2 is available
        let nulib2Path = "/usr/bin/nulib2"
        let homebrewPath = "/opt/homebrew/bin/nulib2"
        let usrLocalPath = "/usr/local/bin/nulib2"
        
        var toolPath: String?
        for path in [nulib2Path, homebrewPath, usrLocalPath] {
            if FileManager.default.fileExists(atPath: path) {
                toolPath = path
                break
            }
        }
        
        // Also check PATH
        if toolPath == nil {
            let whichProcess = Process()
            whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            whichProcess.arguments = ["nulib2"]
            let pipe = Pipe()
            whichProcess.standardOutput = pipe
            whichProcess.standardError = FileHandle.nullDevice
            try? whichProcess.run()
            whichProcess.waitUntilExit()
            
            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    toolPath = path
                }
            }
        }
        
        guard let nulib2 = toolPath else {
            print("   ⚠️ nulib2 not found - install with: brew install nulib2")
            return nil
        }
        
        print("   Using nulib2: \(nulib2)")
        
        // Create temp directory for extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Run nulib2 to extract
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nulib2)
        process.arguments = ["-x", "-e", url.path]
        process.currentDirectoryURL = tempDir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                // Find extracted file
                let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                if let extractedFile = contents.first {
                    let extractedData = try Data(contentsOf: extractedFile)
                    print("   ✅ Extracted \(extractedData.count) bytes via nulib2")
                    return extractedData
                }
            }
        } catch {
            print("   ❌ nulib2 error: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 1 < data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        return UInt32(data[offset]) |
               (UInt32(data[offset + 1]) << 8) |
               (UInt32(data[offset + 2]) << 16) |
               (UInt32(data[offset + 3]) << 24)
    }
    
    private static func padToFloppySize(_ data: Data, expectedSize: Int) -> Data {
        if data.count >= expectedSize {
            return data.prefix(expectedSize)
        }
        var padded = data
        padded.append(contentsOf: [UInt8](repeating: 0, count: expectedSize - data.count))
        return padded
    }
}
