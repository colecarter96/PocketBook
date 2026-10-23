//
//  PocketCloud.swift
//  PocketBook
//

import Foundation
import os

enum PocketCloudStore {
    static let containerID = "iCloud.com.colecarter.PocketBook"

    private static let cloudRoot = OSAllocatedUnfairLock<URL?>(initialState: nil)

    static func prepare() async {
        let root = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: containerID)
        }.value
        cloudRoot.withLock { $0 = root }
        guard root != nil else { return }
        migrate(folder: "NoteImages")
        migrate(folder: "VoiceMemos")
    }

    static func directory(folder: String) -> URL {
        if let cloud = cloudDirectory(folder: folder) {
            return cloud
        }
        return localDirectory(folder: folder)
    }

    static func fileURL(_ fileName: String, folder: String) -> URL {
        let cloudFile = cloudDirectory(folder: folder)?.appendingPathComponent(fileName)
        if let cloudFile, FileManager.default.fileExists(atPath: cloudFile.path) {
            startDownloadIfNeeded(cloudFile)
            return cloudFile
        }
        let localFile = localDirectory(folder: folder).appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: localFile.path) {
            return localFile
        }
        if let cloudFile {
            startDownloadIfNeeded(cloudFile)
            return cloudFile
        }
        return localFile
    }

    private static func cloudDirectory(folder: String) -> URL? {
        guard let root = cloudRoot.withLock({ $0 }) else { return nil }
        let folderURL = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    private static func localDirectory(folder: String) -> URL {
        let folderURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    private static func migrate(folder: String) {
        guard let destination = cloudDirectory(folder: folder) else { return }
        let source = localDirectory(folder: folder)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            try? FileManager.default.setUbiquitous(true, itemAt: file, destinationURL: target)
        }
    }

    private static func startDownloadIfNeeded(_ url: URL) {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
