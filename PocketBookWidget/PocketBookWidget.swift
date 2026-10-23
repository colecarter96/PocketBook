//
//  PocketBookWidget.swift
//  PocketBookWidget
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct PocketBookWidgets: WidgetBundle {
    var body: some Widget {
        NewNoteWidget()
        NoteWidget()
    }
}

struct NewNoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NewNote", provider: NewNoteProvider()) { _ in
            NewNoteWidgetView()
        }
        .configurationDisplayName("New Note")
        .description("Open PocketBook and start writing.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NewNoteEntry: TimelineEntry {
    var date: Date
}

struct NewNoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> NewNoteEntry {
        NewNoteEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (NewNoteEntry) -> Void) {
        completion(NewNoteEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NewNoteEntry>) -> Void) {
        completion(Timeline(entries: [NewNoteEntry(date: .now)], policy: .never))
    }
}

struct NewNoteWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("New Note", systemImage: "plus")
            case .accessoryCircular:
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
            default:
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.medium))
                    Text("New Note")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetURL(URL(string: "pocketbook://new"))
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }
}

struct SelectNoteIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Note"
    static var description = IntentDescription("Choose which note to show.")

    @Parameter(title: "Note")
    var note: WidgetNoteEntity?
}

struct WidgetNoteEntity: AppEntity {
    var id: String
    var body: String
    var createdAt: Date

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note")
    static var defaultQuery = WidgetNoteQuery()

    var displayRepresentation: DisplayRepresentation {
        let line = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? body
        let title = line.count > 80 ? String(line.prefix(80)) : line
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(createdAt.formatted(date: .abbreviated, time: .shortened))"
        )
    }
}

struct WidgetNoteQuery: EntityStringQuery {
    func entities(for identifiers: [WidgetNoteEntity.ID]) async throws -> [WidgetNoteEntity] {
        identifiers.compactMap { id in
            WidgetNoteFile.load().first { $0.id == id }.map(WidgetNoteEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WidgetNoteEntity] {
        WidgetNoteFile.load().map(WidgetNoteEntity.init)
    }

    func entities(matching string: String) async throws -> [WidgetNoteEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = WidgetNoteFile.load().map(WidgetNoteEntity.init)
        guard !needle.isEmpty else { return notes }
        return notes.filter { $0.body.localizedCaseInsensitiveContains(needle) }
    }
}

extension WidgetNoteEntity {
    init(_ record: WidgetNoteRecord) {
        id = record.id
        body = record.body
        createdAt = record.createdAt
    }
}

struct NoteEntry: TimelineEntry {
    var date: Date
    var note: WidgetNoteEntity?
}

struct NoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, note: nil)
    }

    func snapshot(for configuration: SelectNoteIntent, in context: Context) async -> NoteEntry {
        NoteEntry(date: .now, note: fresh(configuration.note))
    }

    func timeline(for configuration: SelectNoteIntent, in context: Context) async -> Timeline<NoteEntry> {
        Timeline(entries: [NoteEntry(date: .now, note: fresh(configuration.note))], policy: .never)
    }

    private func fresh(_ selected: WidgetNoteEntity?) -> WidgetNoteEntity? {
        guard let selected else { return nil }
        if let record = WidgetNoteFile.load().first(where: { $0.id == selected.id }) {
            return WidgetNoteEntity(record)
        }
        return selected
    }
}

struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Note", intent: SelectNoteIntent.self, provider: NoteProvider()) { entry in
            NoteWidgetView(note: entry.note)
        }
        .configurationDisplayName("Note")
        .description("Keep any note on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct NoteWidgetView: View {
    var note: WidgetNoteEntity?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let note {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note.body)
                        .font(.custom("HelveticaNeue-Medium", size: textSize))
                        .foregroundStyle(.primary)
                        .lineLimit(lineLimit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .widgetURL(URL(string: "pocketbook://note/\(note.id)"))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.title3.weight(.medium))
                    Text("Choose a note")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var textSize: CGFloat {
        switch family {
        case .systemSmall: 15
        case .systemMedium: 16
        case .systemLarge: 17
        default: 18
        }
    }

    private var lineLimit: Int {
        switch family {
        case .systemSmall: 6
        case .systemMedium: 5
        case .systemLarge: 14
        default: 22
        }
    }
}
