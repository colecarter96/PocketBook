//
//  PocketCloud.swift
//  PocketBook
//

import Foundation
import os

enum PocketCloudStore {
    static let containerID = "iCloud.com.colecarter.PocketBook"

    private static let cloudRoot = OSAllocatedUnfairLock<URL?>(initialState: nil)
    private static let moveLock = NSLock()

    static func prepare() async {
        let root = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: containerID)
        }.value
        cloudRoot.withLock { $0 = root }
        guard root != nil else { return }
        await Task.detached(priority: .utility) {
            migrate(folder: "NoteImages")
            migrate(folder: "VoiceMemos")
        }.value
    }

    static func localDirectoryURL(folder: String) -> URL {
        localDirectory(folder: folder)
    }

    static func localFileURL(_ fileName: String, folder: String) -> URL {
        localDirectory(folder: folder).appendingPathComponent(fileName)
    }

    static func publish(_ fileName: String, folder: String) {
        moveLock.lock()
        defer { moveLock.unlock() }
        let source = localDirectory(folder: folder).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        guard let destination = cloudDirectory(folder: folder)?.appendingPathComponent(fileName) else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: source)
            return
        }
        try? FileManager.default.setUbiquitous(true, itemAt: source, destinationURL: destination)
    }

    static func remove(_ fileName: String, folder: String) {
        moveLock.lock()
        defer { moveLock.unlock() }
        let local = localDirectory(folder: folder).appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: local.path) {
            try? FileManager.default.removeItem(at: local)
        }
        if let cloud = cloudDirectory(folder: folder)?.appendingPathComponent(fileName),
           FileManager.default.fileExists(atPath: cloud.path) {
            try? FileManager.default.removeItem(at: cloud)
        }
    }

    static func fileNames(in folder: String) -> [String] {
        var names = Set<String>()
        var folders = [localDirectory(folder: folder)]
        if let cloud = cloudDirectory(folder: folder) {
            folders.append(cloud)
        }
        for folderURL in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil
            ) else { continue }
            for file in files {
                names.insert(file.lastPathComponent)
            }
        }
        return Array(names)
    }

    static func directory(folder: String) -> URL {
        localDirectory(folder: folder)
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
        guard cloudDirectory(folder: folder) != nil else { return }
        let source = localDirectory(folder: folder)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            publish(file.lastPathComponent, folder: folder)
        }
    }

    private static func startDownloadIfNeeded(_ url: URL) {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
