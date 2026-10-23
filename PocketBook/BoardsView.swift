//
//  BoardsView.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI

struct BoardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.createdAt, order: .reverse) private var boards: [Board]

    @State private var isCreatingBoard = false
    @State private var newBoardName = ""

    var body: some View {
        NavigationStack {
            Group {
                if boards.isEmpty {
                    emptyState
                } else {
                    boardList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("New List", isPresented: $isCreatingBoard) {
                TextField("Workout, Surf, Project A", text: $newBoardName)
                Button("Create") {
                    createBoard()
                }
                Button("Cancel", role: .cancel) {
                    newBoardName = ""
                }
            }
        }
        .tint(.primary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lists")
                .font(.largeTitle.bold())
            Text("Group your thoughts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Lists you create will live here")
                .pocketBody()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .overlay(alignment: .topTrailing) {
            Button {
                newBoardName = ""
                isCreatingBoard = true
            } label: {
                Image(systemName: "plus")
                    .pocketBody(weight: .semibold)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .accessibilityLabel("New List")
        }
    }

    private var sortedBoards: [Board] {
        boards.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var boardList: some View {
        List {
            Section {
                ForEach(sortedBoards) { board in
                    NavigationLink {
                        BoardDetailView(board: board)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.stack")
                                .pocketBody(weight: .medium)
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(Color(.secondarySystemBackground), in: Circle())
                            Text(board.name)
                                .pocketBody()
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Text("\(board.listedNotes.count)")
                                .pocketBody()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .contextMenu {
                        Button("Delete List", systemImage: "trash", role: .destructive) {
                            modelContext.delete(board)
                            try? modelContext.save()
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(PocketCanvas())
                }
            } header: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lists")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                            .textCase(nil)
                        Text("Group your thoughts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                    Spacer()
                    Button {
                        newBoardName = ""
                        isCreatingBoard = true
                    } label: {
                        Image(systemName: "plus")
                            .pocketBody(weight: .semibold)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New List")
                }
                .padding(.bottom, 8)
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, PocketBarClearance.scroll, for: .scrollContent)
        .background(PocketCanvas())
    }

    private func boardKey(_ board: Board) -> String {
        String(describing: board.persistentModelID)
    }

    private func noteCountLabel(for board: Board) -> String {
        let count = board.listedNotes.count
        return count == 1 ? "1 note" : "\(count) notes"
    }

    private func createBoard() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(Board(name: name))
        try? modelContext.save()
        newBoardName = ""
    }

}

struct BoardDetailView: View {
    @Bindable var board: Board
    @Environment(\.modelContext) private var modelContext
    @Environment(RecentDelete.self) private var recentDelete

    private var sortedNotes: [Note] {
        board.listedNotes.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if sortedNotes.isEmpty {
                Text("Nothing on this list yet")
                    .pocketBody()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                List {
                    ForEach(sortedNotes) { note in
                        NavigationLink {
                            NoteDetailView(note: note, sourceBoard: board)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(note.text.isEmpty ? "Empty note" : note.text)
                                    .pocketBody()
                                    .foregroundStyle(note.text.isEmpty ? .tertiary : .primary)

                                Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(PocketCanvas())
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteNote(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                note.toggleBoard(board)
                                try? modelContext.save()
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .tint(Color(white: 0.45))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, PocketBarClearance.scroll, for: .scrollContent)
                .background(PocketCanvas())
            }
        }
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Note", systemImage: "plus") {
                    addNoteToBoard()
                }
            }
        }
    }

    private func addNoteToBoard() {
        let note = Note(text: "")
        modelContext.insert(note)
        note.toggleBoard(board)
        try? modelContext.save()
    }

    private func deleteNote(_ note: Note) {
        recentDelete.remember(note)
        modelContext.delete(note)
        try? modelContext.save()
    }
}

struct BoardPickerSheet: View {
    @Bindable var note: Note
    var completesOnPick = false
    var onPlaced: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.createdAt, order: .reverse) private var boards: [Board]

    @State private var newBoardName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ThumbCloud(items: boards, key: { String(describing: $0.persistentModelID) }, bottomReserve: 16) { board in
                    Button {
                        if completesOnPick {
                            if !note.isOn(board) {
                                note.toggleBoard(board)
                            }
                            try? modelContext.save()
                            onPlaced()
                            dismiss()
                        } else {
                            note.toggleBoard(board)
                            try? modelContext.save()
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text(board.name)
                                .font(.system(ThumbCloudStyle.size(for: String(describing: board.persistentModelID)), design: .serif))
                                .foregroundStyle(.primary)
                            if note.isOn(board) {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    TextField("New list", text: $newBoardName)
                        .pocketBody()
                    Button("Add") {
                        createBoardAndAssign()
                    }
                    .disabled(newBoardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .tint(.primary)
        .presentationDetents([.medium, .large])
    }

    private func createBoardAndAssign() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let board = Board(name: name)
        modelContext.insert(board)
        note.toggleBoard(board)
        try? modelContext.save()
        newBoardName = ""
        if completesOnPick {
            onPlaced()
            dismiss()
        }
    }
}

private enum ThumbCloudStyle {
    static func size(for key: String) -> Font.TextStyle {
        switch stableHash(key) % 3 {
        case 0: .body
        case 1: .title3
        default: .title2
        }
    }
}

private struct CloudItemSize: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]

    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ThumbCloud<Item: Identifiable, Content: View>: View {
    var items: [Item]
    var key: (Item) -> String
    var bottomReserve: CGFloat = 120
    @ViewBuilder var content: (Item) -> Content

    @State private var measured: [String: CGSize] = [:]

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = ThumbSpot.columnWidth(in: geometry.size.width)
            let layout = ThumbSpot.layout(
                entries: items.map { item in
                    let itemKey = key(item)
                    let size = measured[itemKey] ?? CGSize(width: min(columnWidth, 88), height: 36)
                    return (key: itemKey, size: size)
                },
                viewport: geometry.size,
                columnWidth: columnWidth,
                bottomReserve: bottomReserve
            )
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: geometry.size.width, height: layout.height)
                    ForEach(items) { item in
                        content(item)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: columnWidth)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: CloudItemSize.self,
                                        value: [key(item): proxy.size]
                                    )
                                }
                            }
                            .position(layout.positions[key(item)] ?? CGPoint(x: geometry.size.width / 2, y: layout.height - bottomReserve))
                    }
                }
                .frame(width: geometry.size.width, height: layout.height)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .onPreferenceChange(CloudItemSize.self) { next in
                guard sizesChanged(measured, next) else { return }
                measured = next
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sizesChanged(_ current: [String: CGSize], _ next: [String: CGSize]) -> Bool {
        guard current.count == next.count else { return true }
        for (itemKey, size) in next {
            guard let existing = current[itemKey] else { return true }
            if abs(existing.width - size.width) > 1 || abs(existing.height - size.height) > 1 {
                return true
            }
        }
        return false
    }
}

private enum ThumbSpot {
    static func columnWidth(in width: CGFloat) -> CGFloat {
        let sideInset: CGFloat = 18
        let gap: CGFloat = 16
        return max((width - sideInset * 2 - gap * 2) / 3, 1)
    }

    static func layout(
        entries: [(key: String, size: CGSize)],
        viewport: CGSize,
        columnWidth: CGFloat,
        bottomReserve: CGFloat
    ) -> (positions: [String: CGPoint], height: CGFloat) {
        let sideInset: CGFloat = 18
        let gapX: CGFloat = 16
        let gapY: CGFloat = 18
        let columnX = (0..<3).map { index in
            sideInset + columnWidth / 2 + CGFloat(index) * (columnWidth + gapX)
        }
        let ordered = entries
            .map { entry in
                (key: entry.key, hash: stableHash(entry.key), size: entry.size, column: Int(stableHash(entry.key) % 3))
            }
            .sorted { $0.hash < $1.hash }

        var cursor = [CGFloat](repeating: 0, count: 3)
        var fromBottom: [(key: String, point: CGPoint)] = []
        for entry in ordered {
            let y = cursor[entry.column] + gapY + entry.size.height / 2
            cursor[entry.column] = y + entry.size.height / 2
            let spare = max(0, columnWidth - entry.size.width)
            let jitter = (CGFloat(entry.hash % 1000) / 999 - 0.5) * spare
            fromBottom.append((
                key: entry.key,
                point: CGPoint(x: columnX[entry.column] + jitter, y: y)
            ))
        }

        let packed = (cursor.max() ?? 0) + gapY
        let height = max(viewport.height, packed + bottomReserve + 8)
        var positions: [String: CGPoint] = [:]
        for entry in fromBottom {
            positions[entry.key] = CGPoint(
                x: entry.point.x,
                y: height - bottomReserve - entry.point.y
            )
        }
        return (positions, height)
    }
}

private func stableHash(_ key: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in key.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}
