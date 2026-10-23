//
//  WidgetNoteFile.swift
//  PocketBook
//

import Foundation

struct WidgetNoteRecord: Codable, Identifiable, Hashable {
    var id: String
    var body: String
    var createdAt: Date
}

enum WidgetNoteFile {
    static let groupID = "group.com.colecarter.PocketBook"

    static func load() -> [WidgetNoteRecord] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WidgetNoteRecord].self, from: data)) ?? []
    }

    static func save(_ notes: [WidgetNoteRecord]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("notes.json")
    }
}
