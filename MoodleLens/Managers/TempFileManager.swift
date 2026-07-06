//
//  TempFileManager.swift
//  MoodleLens
//
//  Created on 4/15/25.
//

import Foundation
import AppKit

/// A manager class for handling temporary files created by the application
/// Ensures proper lifecycle management and cleanup of sensitive data
class TempFileManager {

    // Singleton instance
    static let shared = TempFileManager()

    // Registry of temporary files created by the application
    private var tempFileRegistry: [URL] = []

    // Base directory for app-specific temporary files
    private let appTempDirectory: URL

    // Timer for periodic cleanup
    private var cleanupTimer: Timer?

    // How often to clean up old files (in seconds)
    private let cleanupInterval: TimeInterval = 3600 // 1 hour

    // How old files should be to be considered for cleanup (in seconds)
    private let fileAgeThreshold: TimeInterval = 86400 // 24 hours

    private init() {
        // Create a dedicated directory for app temp files
        let tempDir = FileManager.default.temporaryDirectory
        appTempDirectory = tempDir.appendingPathComponent("io.github.volodymyryelisieiev.moodlelens", isDirectory: true)

        ensureAppTempDirectoryExists()

        // Register for app termination to clean up files
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        // Start periodic cleanup timer
        startCleanupTimer()

        logDebug("TempFileManager initialized")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupTimer?.invalidate()
    }

    /// Starts the timer for periodic cleanup of old temporary files
    private func startCleanupTimer() {
        // Stop any existing timer
        cleanupTimer?.invalidate()

        // Create a new timer that fires periodically
        cleanupTimer = Timer.scheduledTimer(
            timeInterval: cleanupInterval,
            target: self,
            selector: #selector(periodicCleanup),
            userInfo: nil,
            repeats: true
        )

        // Add the timer to the common run loop mode to ensure it fires even when UI is busy
        RunLoop.current.add(cleanupTimer!, forMode: .common)

        logDebug("TempFileManager cleanup timer started")
    }

    /// Periodic cleanup handler called by the timer
    @objc private func periodicCleanup() {
        logDebug("TempFileManager periodic cleanup started")
        DispatchQueue.global(qos: .background).async {
            let deletedCount = self.cleanupOldTempFiles(olderThan: self.fileAgeThreshold)
            self.logDebug("TempFileManager periodic cleanup removed \(deletedCount) old files")
        }
    }

    /// Register a file URL that should be tracked for cleanup
    /// - Parameter fileURL: The URL of the temporary file
    func registerTempFile(_ fileURL: URL) {
        tempFileRegistry.append(fileURL)
        logDebug("Registered temporary file")
    }

    /// Create a new temporary file URL for the given purpose and register it
    /// - Parameters:
    ///   - prefix: A prefix to identify the file type (e.g., "recording", "screenshot")
    ///   - extension: The file extension (e.g., "m4a", "png")
    /// - Returns: A URL for a new temporary file
    func createTempFileURL(prefix: String, extension: String) -> URL {
        ensureAppTempDirectoryExists()

        // Generate a unique filename with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "\(prefix)_\(dateString).\(`extension`)"

        // Create the full URL in our app temp directory
        let fileURL = appTempDirectory.appendingPathComponent(fileName)

        // Register this file automatically
        registerTempFile(fileURL)

        return fileURL
    }

    /// Delete a specific temporary file
    /// - Parameter fileURL: URL of the file to delete
    /// - Returns: Whether the deletion was successful
    @discardableResult
    func deleteTempFile(_ fileURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)

                // Remove from registry
                if let index = tempFileRegistry.firstIndex(of: fileURL) {
                    tempFileRegistry.remove(at: index)
                }

                logDebug("Deleted temporary file")
                return true
            } else {
                logDebug("Temporary file already deleted")
                // Still remove from registry
                if let index = tempFileRegistry.firstIndex(of: fileURL) {
                    tempFileRegistry.remove(at: index)
                }
                return true
            }
        } catch {
            logDebug("Error deleting temporary file: \(error.localizedDescription)")
            return false
        }
    }

    /// Clean up all registered temporary files
    /// - Returns: Number of successfully deleted files
    @discardableResult
    func cleanupAllTempFiles() -> Int {
        var deletedCount = 0
        var filesToDelete = Set(tempFileRegistry)

        if FileManager.default.fileExists(atPath: appTempDirectory.path) {
            do {
                let directoryFiles = try FileManager.default.contentsOfDirectory(
                    at: appTempDirectory,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                filesToDelete.formUnion(directoryFiles)
            } catch {
                logDebug("Error scanning temp directory: \(error.localizedDescription)")
            }
        }

        for fileURL in filesToDelete {
            if deleteTempFile(fileURL) {
                deletedCount += 1
            }
        }

        removeAppTempDirectoryIfEmpty()
        logDebug("Cleaned up \(deletedCount) temporary files")
        return deletedCount
    }

    /// Clean up old temporary files (older than the specified time interval)
    /// - Parameter olderThan: Time interval (in seconds) for file age threshold
    /// - Returns: Number of successfully deleted files
    @discardableResult
    func cleanupOldTempFiles(olderThan timeInterval: TimeInterval = 3600) -> Int {
        var deletedCount = 0
        let currentDate = Date()
        guard FileManager.default.fileExists(atPath: appTempDirectory.path) else { return 0 }

        do {
            // Get all files in the temporary directory
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: appTempDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            for fileURL in fileURLs {
                do {
                    // Get file creation date
                    let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                    if let creationDate = resourceValues.creationDate {
                        // Delete if older than threshold
                        if currentDate.timeIntervalSince(creationDate) > timeInterval {
                            try FileManager.default.removeItem(at: fileURL)
                            deletedCount += 1
                            logDebug("Deleted old temporary file")

                            // Update registry
                            if let index = tempFileRegistry.firstIndex(of: fileURL) {
                                tempFileRegistry.remove(at: index)
                            }
                        }
                    }
                } catch {
                    logDebug("Error processing temporary file: \(error.localizedDescription)")
                }
            }
        } catch {
            logDebug("Error scanning temp directory: \(error.localizedDescription)")
        }

        removeAppTempDirectoryIfEmpty()
        logDebug("Cleaned up \(deletedCount) old temporary files")
        return deletedCount
    }

    /// Handles application termination by cleaning up all temporary files
    @objc private func applicationWillTerminate(_ notification: Notification) {
        logDebug("Application terminating, cleaning up temporary files")
        cleanupAllTempFiles()
    }

    private func ensureAppTempDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: appTempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func removeAppTempDirectoryIfEmpty() {
        guard FileManager.default.fileExists(atPath: appTempDirectory.path),
              let remainingFiles = try? FileManager.default.contentsOfDirectory(
                at: appTempDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
              ),
              remainingFiles.isEmpty else {
            return
        }

        try? FileManager.default.removeItem(at: appTempDirectory)
    }

    private func logDebug(_ message: String) {
        if DevelopmentConfig.enableVerboseLogging {
            print(message)
        }
    }
}
