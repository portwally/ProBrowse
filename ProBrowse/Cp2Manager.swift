//
//  Cp2Manager.swift
//  ProBrowse
//
//  CiderPress2 (cp2) integration for disk image operations
//

import Foundation

class Cp2Manager {
    static let shared = Cp2Manager()
    
    private let cp2Path: URL
    
    private init() {
        // Find cp2 in bundle resources
        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("cp2_1.1.1_osx-x64_sc/cp2") {
            cp2Path = bundlePath
            print("🔧 Cp2Manager initialized")
            print("📍 cp2 Path: \(cp2Path.path)")
        } else {
            fatalError("cp2 not found in bundle")
        }
    }
    
    // MARK: - Execute cp2 Command
    
    @discardableResult
    private func execute(arguments: [String], completion: @escaping (Bool, String) -> Void) -> Process {
        let process = Process()
        process.executableURL = cp2Path
        process.arguments = arguments
        
        // Make sure cp2 is executable
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cp2Path.path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: cp2Path.path)
                let permissions = attributes[.posixPermissions] as? NSNumber
                print("📋 cp2 permissions: \(permissions?.intValue ?? 0)")
                
                // Make executable if needed (chmod +x)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cp2Path.path)
            } catch {
                print("⚠️ Could not set permissions: \(error)")
            }
        } else {
            print("❌ ERROR: cp2 not found at: \(cp2Path.path)")
            DispatchQueue.main.async {
                completion(false, "cp2 binary not found at: \(self.cp2Path.path)")
            }
            return process
        }
        
        // DEBUG: Print command
        let commandString = ([cp2Path.path] + arguments).joined(separator: " ")
        print("🔧 cp2 Command: \(commandString)")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                print("📤 cp2 Output: \(output)")
                print("📊 Exit Code: \(process.terminationStatus)")
                
                // cp2 returns 0 on success
                let success = process.terminationStatus == 0
                
                DispatchQueue.main.async {
                    completion(success, output)
                }
            }
            
        } catch {
            print("❌ cp2 Launch Error: \(error)")
            DispatchQueue.main.async {
                completion(false, "Failed to launch cp2: \(error.localizedDescription)")
            }
        }
        
        return process
    }
    
    // MARK: - Catalog
    
    /// Lists contents of disk image
    func catalog(diskImage: URL, completion: @escaping (Bool, String) -> Void) {
        let args = [
            "catalog",
            diskImage.path
        ]
        
        execute(arguments: args) { success, output in
            if !success {
                print("cp2 CATALOG failed: \(output)")
            }
            completion(success, output)
        }
    }
    
    // MARK: - Get Volume Name
    
    /// Get the volume name from disk image using CATALOG
    func getVolumeName(diskImage: URL, completion: @escaping (String?) -> Void) {
        catalog(diskImage: diskImage) { success, output in
            if success {
                // Parse volume name from CATALOG output
                // Format: ProDOS "VOLUMENAME"
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("ProDOS") && line.contains("\"") {
                        // Extract volume name between quotes
                        if let start = line.firstIndex(of: "\""),
                           let end = line[line.index(after: start)...].firstIndex(of: "\"") {
                            let volumeName = String(line[line.index(after: start)..<end])
                            print("📀 Detected volume name: \(volumeName)")
                            completion(volumeName)
                            return
                        }
                    }
                }
            }
            print("⚠️ Could not detect volume name from CATALOG")
            completion(nil)
        }
    }
    
    // MARK: - Extract File
    
    /// Extracts a file from the disk image to a temporary directory
    func extractFile(diskImage: URL, fileName: String, completion: @escaping (Bool, URL?) -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
        
        // Change working directory to temp for extraction
        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDir.path)
        
        let args = [
            "extract",
            diskImage.path,
            fileName
        ]
        
        execute(arguments: args) { success, output in
            // Restore original directory
            FileManager.default.changeCurrentDirectoryPath(originalDir)
            
            if success {
                let extractedFile = tempDir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: extractedFile.path) {
                    print("✅ Extracted to: \(extractedFile.path)")
                    completion(true, extractedFile)
                    return
                }
            }
            
            print("❌ cp2 EXTRACT failed: \(output)")
            completion(false, nil)
        }
    }
    
    // MARK: - Add File
    
    /// Adds a file to the disk image
    func addFile(diskImage: URL, filePath: URL, completion: @escaping (Bool) -> Void) {
        let args = [
            "add",
            diskImage.path,
            filePath.path
        ]
        
        execute(arguments: args) { success, output in
            if !success {
                print("cp2 ADD failed: \(output)")
            }
            completion(success)
        }
    }
    
    // MARK: - Copy File Between Images
    
    /// Copies a file from one disk image to another
    func copyFile(from sourceImage: URL, to targetImage: URL, fileName: String, sourceVolume: String, completion: @escaping (Bool) -> Void) {
        print("🔄 copyFile: \(fileName)")
        print("   From: \(sourceImage.path)")
        print("   To: \(targetImage.path)")
        print("   Source Volume: \(sourceVolume)")
        
        // Extract from source
        extractFile(diskImage: sourceImage, fileName: fileName) { extractSuccess, extractedFile in
            guard extractSuccess, let tempFile = extractedFile else {
                print("   ❌ Extract failed")
                completion(false)
                return
            }
            
            print("   ✅ Extract succeeded: \(tempFile.lastPathComponent)")
            print("   Now adding to target...")
            
            // Add to target
            self.addFile(diskImage: targetImage, filePath: tempFile) { addSuccess in
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempFile)
                
                if addSuccess {
                    print("   ✅ Copy completed successfully")
                } else {
                    print("   ❌ Add failed")
                }
                
                completion(addSuccess)
            }
        }
    }
    
    // MARK: - Create Disk Image
    
    /// Creates a new ProDOS disk image
    func createDiskImage(at path: URL, volumeName: String, size: String, completion: @escaping (Bool, String) -> Void) {
        let args = [
            "create-disk-image",
            path.path,
            "prodos",
            volumeName,
            size
        ]
        
        execute(arguments: args) { success, output in
            if !success {
                print("cp2 CREATE-DISK-IMAGE failed: \(output)")
            }
            completion(success, output)
        }
    }
}
