//
//  WidgetNoteLibrary.swift
//  PocketBook
//

import CoreData
import SwiftData
import WidgetKit

enum WidgetNoteLibrary {
    private static var publishing = false

    static func publish(from context: ModelContext) {
        guard !publishing else { return }
        publishing = true
        defer { publishing = false }

        let notes = (try? context.fetch(FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))) ?? []

        var assigned = false
        for note in notes where note.widgetKey.isEmpty && !note.isBlank {
            note.widgetKey = UUID().uuidString
            assigned = true
        }
        if assigned {
            try? context.save()
        }

        let records = notes.compactMap { note -> WidgetNoteRecord? in
            let body = preview(of: note)
            guard !body.isEmpty, !note.widgetKey.isEmpty else { return nil }
            return WidgetNoteRecord(id: note.widgetKey, body: body, createdAt: note.createdAt)
        }
        WidgetNoteFile.save(records)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func preview(of note: Note) -> String {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty { return transcript }
        if note.audioFileName != nil { return "Voice memo" }
        if !note.imageFileNames.isEmpty { return "Photo" }
        return ""
    }
}
