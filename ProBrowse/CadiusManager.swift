//
//  CadiusManager.swift
//  ProBrowse
//
//  Wrapper for Cadius command line tool from Brutal Deluxe
//  https://brutaldeluxe.fr/products/crossdevtools/cadius/
//

import Foundation

class CadiusManager {
    static let shared = CadiusManager()
    
    private var cadiusPath: URL {
        // Check multiple locations in order of preference
        
        // 1. Bundle Resources (best for distribution)
        if let bundlePath = Bundle.main.url(forResource: "cadius", withExtension: nil) {
            print("✅ Found Cadius in Bundle: \(bundlePath.path)")
            return bundlePath
        }
        
        // 2. ~/bin/cadius (standard location)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let binPath = homeDir.appendingPathComponent("bin/cadius")
        if FileManager.default.fileExists(atPath: binPath.path) {
            print("✅ Found Cadius in ~/bin: \(binPath.path)")
            return binPath
        }
        
        // 3. ~/Downloads/cadius (for testing)
        let downloadsPath = homeDir.appendingPathComponent("Downloads/cadius")
        if FileManager.default.fileExists(atPath: downloadsPath.path) {
            print("✅ Found Cadius in Downloads: \(downloadsPath.path)")
            return downloadsPath
        }
        
        // 4. /usr/local/bin/cadius
        let usrLocalPath = URL(fileURLWithPath: "/usr/local/bin/cadius")
        if FileManager.default.fileExists(atPath: usrLocalPath.path) {
            print("✅ Found Cadius in /usr/local/bin: \(usrLocalPath.path)")
            return usrLocalPath
        }
        
        // Fallback (will likely fail but we'll see the error)
        print("❌ WARNING: Cadius NOT found in any standard location!")
        print("   Looked in:")
        print("   - Bundle Resources")
        print("   - ~/bin/cadius")
        print("   - ~/Downloads/cadius")
        print("   - /usr/local/bin/cadius")
        return binPath // Return ~/bin as fallback
    }
    
    private init() {
        // Log cadius path on init
        print("🔧 CadiusManager initialized")
        print("📍 Cadius Path: \(cadiusPath.path)")
    }
    
    // MARK: - Execute Cadius Command
    
    @discardableResult
    private func execute(arguments: [String], completion: @escaping (Bool, String) -> Void) -> Process {
        let process = Process()
        
        // Check if we're on Apple Silicon and need Rosetta for x86_64 Cadius
        #if arch(arm64)
        // Use arch -x86_64 to run Intel binary via Rosetta
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", cadiusPath.path] + arguments
        #else
        // Intel Mac - run directly
        process.executableURL = cadiusPath
        process.arguments = arguments
        #endif
        
        // Make sure cadius is executable
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cadiusPath.path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: cadiusPath.path)
                let permissions = attributes[.posixPermissions] as? NSNumber
                print("📋 Cadius permissions: \(permissions?.intValue ?? 0)")
                
                // Make executable if needed (chmod +x)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cadiusPath.path)
            } catch {
                print("⚠️ Could not set permissions: \(error)")
            }
        } else {
            print("❌ ERROR: Cadius not found at: \(cadiusPath.path)")
            DispatchQueue.main.async {
                completion(false, "Cadius binary not found at: \(self.cadiusPath.path)")
            }
            return process
        }
        
        // DEBUG: Print command
        #if arch(arm64)
        let commandString = (["/usr/bin/arch", "-x86_64", cadiusPath.path] + arguments).joined(separator: " ")
        #else
        let commandString = ([cadiusPath.path] + arguments).joined(separator: " ")
        #endif
        print("🔧 Cadius Command: \(commandString)")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                print("📤 Cadius Output: \(output)")
                print("📊 Exit Code: \(process.terminationStatus)")
                
                // Cadius returns 0 even on errors, so check output for "Error"
                let success = process.terminationStatus == 0 && !output.contains("Error :")
                
                if !success && output.contains("Error :") {
                    print("❌ Cadius reported error in output")
                }
                
                DispatchQueue.main.async {
                    completion(success, output)
                }
            }
            
        } catch {
            print("❌ Cadius Launch Error: \(error)")
            DispatchQueue.main.async {
                completion(false, "Failed to launch Cadius: \(error.localizedDescription)")
            }
        }
        
        return process
    }
    
    // MARK: - Create Disk Image
    
    /// CREATEVOLUME <disk_image> <volume_name> [<size>]
    /// Creates a ProDOS disk image
    /// size: 140KB, 800KB, 1440KB, 32MB, etc.
    func createVolume(volumeName: String, imagePath: URL, size: String = "800KB", completion: @escaping (Bool, String) -> Void) {
        let args = [
            "CREATEVOLUME",
            imagePath.path,
            volumeName,
            size
        ]
        
        execute(arguments: args, completion: completion)
    }
    
    // MARK: - Add File
    
    /// ADDFILE <disk_image> <prodos_folder> <file_path>
    /// Adds a file to the disk image
    func addFile(diskImage: URL, filePath: URL, fileName: String? = nil, targetFolder: String = "/", completion: @escaping (Bool) -> Void) {
        _ = fileName ?? filePath.lastPathComponent
        
        let args = [
            "ADDFILE",
            diskImage.path,
            targetFolder,
            filePath.path
        ]
        
        execute(arguments: args) { success, output in
            if !success {
                print("Cadius ADDFILE failed: \(output)")
            }
            completion(success)
        }
    }
    
    // MARK: - Extract File
    
    /// EXTRACTFILE <disk_image> <prodos_path> [<output_directory>]
    /// Extracts a file from the disk image
    func extractFile(diskImage: URL, prodosPath: String, outputPath: URL, completion: @escaping (Bool) -> Void) {
        // Cadius wants the OUTPUT DIRECTORY, not the full file path
        let outputDir = outputPath.deletingLastPathComponent()
        
        let args = [
            "EXTRACTFILE",
            diskImage.path,
            prodosPath,
            outputDir.path
        ]
        
        execute(arguments: args) { success, output in
            if !success {
                print("Cadius EXTRACTFILE failed: \(output)")
            }
            completion(success)
        }
    }
    
    // MARK: - Delete File
    
    /// DELETEFILE <disk_image> <prodos_path>
    /// Deletes a file from the disk image
    func deleteFile(diskImage: URL, prodosPath: String, completion: @escaping (Bool) -> Void) {
        let args = [
            "DELETEFILE",
            diskImage.path,
            prodosPath
        ]
        
        execute(arguments: args) { success, output in
            if !success {
                print("Cadius DELETEFILE failed: \(output)")
            }
            completion(success)
        }
    }
    
    // MARK: - Create Folder
    
    /// CREATEFOLDER <disk_image> <prodos_folder>
    /// Creates a folder in the disk image
    func createFolder(diskImage: URL, folderPath: String, completion: @escaping (Bool) -> Void) {
        let args = [
            "CREATEFOLDER",
            diskImage.path,
            folderPath
        ]
        
        execute(arguments: args) { success, output in
            if !success {
                print("Cadius CREATEFOLDER failed: \(output)")
            }
            completion(success)
        }
    }
    
    // MARK: - Get Volume Name
    
    /// Get the actual volume name from disk image using CATALOG
    func getVolumeName(diskImage: URL, completion: @escaping (String?) -> Void) {
        // CATALOG doesn't take a folder parameter
        let args = [
            "CATALOG",
            diskImage.path
        ]
        
        execute(arguments: args) { success, output in
            if success {
                // Parse volume name from CATALOG output
                // Format: "/VOLUMENAME/"
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    // Look for line starting with "/"
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("/") && trimmed.hasSuffix("/") && trimmed.count > 2 {
                        // Extract volume name between slashes
                        let volumeName = String(trimmed.dropFirst().dropLast())
                        print("📀 Detected volume name: \(volumeName)")
                        completion(volumeName)
                        return
                    }
                }
            }
            print("⚠️ Could not detect volume name from CATALOG")
            completion(nil)
        }
    }
    
    // MARK: - Catalog
    
    /// CATALOG <disk_image> [<prodos_folder>]
    /// Lists contents of disk image
    func catalog(diskImage: URL, folder: String = "/", completion: @escaping (Bool, String) -> Void) {
        let args = [
            "CATALOG",
            diskImage.path,
            folder
        ]
        
        execute(arguments: args, completion: completion)
    }
    
    // MARK: - Verify Image
    
    /// VERIFYVOLUME <disk_image>
    /// Verifies the integrity of the disk image
    func verifyVolume(diskImage: URL, completion: @escaping (Bool, String) -> Void) {
        let args = [
            "VERIFYVOLUME",
            diskImage.path
        ]
        
        execute(arguments: args, completion: completion)
    }
    
    // MARK: - Copy File Between Images
    
    /// Helper to copy a file from one disk image to another
    func copyFile(from sourceImage: URL, to targetImage: URL, fileName: String, sourceVolume: String, completion: @escaping (Bool) -> Void) {
        print("🔄 copyFile: \(fileName)")
        print("   From: \(sourceImage.path)")
        print("   To: \(targetImage.path)")
        print("   Source Volume: \(sourceVolume)")
        
        // First extract from source
        let tempDir = FileManager.default.temporaryDirectory
        let expectedTempURL = tempDir.appendingPathComponent(fileName)
        print("   Temp: \(expectedTempURL.path)")
        
        // Use volume name in ProDOS path
        let prodosPath = "/\(sourceVolume)/\(fileName)"
        print("   ProDOS Path: \(prodosPath)")
        
        extractFile(diskImage: sourceImage, prodosPath: prodosPath, outputPath: expectedTempURL) { extractSuccess in
            print("   Extract result: \(extractSuccess)")
            guard extractSuccess else {
                print("   ❌ Extract failed")
                completion(false)
                return
            }
            
            print("   ✅ Extract succeeded, now adding to target...")
            
            // Cadius adds file type suffix (e.g. #060000), so find the actual file
            do {
                let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                // Look for files starting with our filename
                let extractedFiles = tempFiles.filter { $0.lastPathComponent.hasPrefix(fileName) }
                
                guard let originalTempFile = extractedFiles.first else {
                    print("   ❌ Could not find extracted file in temp directory")
                    completion(false)
                    return
                }
                
                print("   📁 Found extracted file: \(originalTempFile.lastPathComponent)")
                
                // Rename to remove the #type suffix for ADDFILE
                let cleanTempFile = tempDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: cleanTempFile) // Remove if exists
                try FileManager.default.moveItem(at: originalTempFile, to: cleanTempFile)
                print("   🔄 Renamed to: \(cleanTempFile.lastPathComponent)")
                
                // Then add to target
                self.addFile(diskImage: targetImage, filePath: cleanTempFile, fileName: fileName) { addSuccess in
                    print("   Add result: \(addSuccess)")
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: cleanTempFile)
                    
                    if addSuccess {
                        print("   ✅ Copy completed successfully")
                    } else {
                        print("   ❌ Add failed")
                    }
                    
                    completion(addSuccess)
                }
            } catch {
                print("   ❌ Error finding extracted file: \(error)")
                completion(false)
            }
        }
    }
    
    // MARK: - Rename File
    
    /// RENAMEFILE <disk_image> <prodos_path> <new_name>
    /// Renames a file or folder
    func renameFile(diskImage: URL, prodosPath: String, newName: String, completion: @escaping (Bool) -> Void) {
        let args = [
            "RENAMEFILE",
            diskImage.path,
            prodosPath,
            newName
        ]
        
        execute(arguments: args) { success, output in
            if !success {
                print("Cadius RENAMEFILE failed: \(output)")
            }
            completion(success)
        }
    }
}
