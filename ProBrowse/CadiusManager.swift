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
        // Cadius binary should be in app bundle Resources
        if let bundlePath = Bundle.main.url(forResource: "cadius", withExtension: nil) {
            return bundlePath
        }
        
        // Fallback to ~/bin/cadius
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent("bin/cadius")
    }
    
    private init() {}
    
    // MARK: - Execute Cadius Command
    
    @discardableResult
    private func execute(arguments: [String], completion: @escaping (Bool, String) -> Void) -> Process {
        let process = Process()
        process.executableURL = cadiusPath
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    completion(process.terminationStatus == 0, output)
                }
            }
            
        } catch {
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
        let name = fileName ?? filePath.lastPathComponent
        
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
    
    /// EXTRACTFILE <disk_image> <prodos_path> [<output_file>]
    /// Extracts a file from the disk image
    func extractFile(diskImage: URL, prodosPath: String, outputPath: URL, completion: @escaping (Bool) -> Void) {
        let args = [
            "EXTRACTFILE",
            diskImage.path,
            prodosPath,
            outputPath.path
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
    func copyFile(from sourceImage: URL, to targetImage: URL, fileName: String, completion: @escaping (Bool) -> Void) {
        // First extract from source
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        extractFile(diskImage: sourceImage, prodosPath: "/\(fileName)", outputPath: tempURL) { extractSuccess in
            guard extractSuccess else {
                completion(false)
                return
            }
            
            // Then add to target
            self.addFile(diskImage: targetImage, filePath: tempURL, fileName: fileName) { addSuccess in
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                completion(addSuccess)
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
