//
//  TimelineView.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI
import UIKit

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    @FocusState private var focusedNoteID: PersistentIdentifier?
    @State private var pendingFocusID: PersistentIdentifier?
    @State private var railProgress: CGFloat = 0
    @State private var railDate: Date?
    @State private var isDraggingRail = false
    @State private var canScrollTimeline = false
    @State private var timelineHeight: CGFloat = 0
    @State private var hapticNoteIndex = 0
    @State private var railImpactToken = 0
    @State private var swipedNoteID: PersistentIdentifier?

    private var isEditing: Bool { focusedNoteID != nil }
    private var canUseRail: Bool {
        notes.count >= 8 && canScrollTimeline && !isEditing && swipedNoteID == nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    emptyState
                } else {
                    timeline
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Save") {
                        endEditing()
                    }
                    .fontWeight(.medium)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isEditing {
                    composeButton
                        .padding(.trailing, 30)
                        .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sensoryFeedback(.selection, trigger: hapticNoteIndex)
        .sensoryFeedback(.impact(weight: .heavy), trigger: railImpactToken)
        .tint(.primary)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                persist()
            }
        }
    }

    private var composeButton: some View {
        Button(action: startNewNote) {
            Image(systemName: "plus")
                .font(.title3.weight(.medium))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
        }
        .accessibilityLabel("New Note")
    }

    private var emptyState: some View {
        Text("Nothing captured yet")
            .font(.system(.body, design: .serif))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Jot away, DrBoss...")
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 28)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: firstNoteTopInset, alignment: .topLeading)
                .id(TimelineAnchor.top)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    endEditing()
                }

                ForEach(notes) { note in
                    NoteRow(
                        note: note,
                        focusedNoteID: $focusedNoteID,
                        pendingFocusID: $pendingFocusID,
                        swipedNoteID: $swipedNoteID,
                        onDelete: { deleteNote(note) }
                    )
                    .id(note.persistentModelID)
                    .listRowInsets(EdgeInsets(
                        top: 2,
                        leading: 20,
                        bottom: 2,
                        trailing: 12
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(.systemBackground))
                }

                Color.clear
                    .frame(minHeight: 240)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        endEditing()
                    }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .onScrollGeometryChange(for: TimelineScrollState.self) { geometry in
                TimelineScrollState(geometry: geometry)
            } action: { oldState, newState in
                canScrollTimeline = newState.canScroll
                timelineHeight = newState.containerHeight
                guard !isDraggingRail else { return }
                railProgress = newState.progress
                registerPassedNote(at: newState.progress)
            }
            .overlay(alignment: .trailing) {
                if canUseRail {
                    TimeRail(
                        progress: railProgress,
                        date: railDate,
                        isDragging: isDraggingRail,
                        onDragChanged: { progress in
                            scrub(to: progress, proxy: proxy)
                        },
                        onDragEnded: {
                            isDraggingRail = false
                            railImpactToken += 1
                            persist()
                        }
                    )
                    .padding(.top, 28)
                    .padding(.bottom, 96)
                }
            }
        }
    }

    private func scrub(to progress: CGFloat, proxy: ScrollViewProxy) {
        guard !notes.isEmpty else { return }

        if !isDraggingRail {
            endEditing()
            railImpactToken += 1
        }

        isDraggingRail = true

        let clamped = min(1, max(0, progress))
        railProgress = clamped

        let index = noteIndex(for: clamped)
        let note = notes[index]
        railDate = note.createdAt
        registerPassedNote(at: clamped)

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            if index == 0 {
                proxy.scrollTo(TimelineAnchor.top, anchor: .top)
            } else {
                proxy.scrollTo(note.persistentModelID, anchor: .top)
            }
        }
    }

    private var firstNoteTopInset: CGFloat {
        let height = timelineHeight > 0 ? timelineHeight : 700
        return height * 0.25
    }

    private func noteIndex(for progress: CGFloat) -> Int {
        guard notes.count > 1 else { return 0 }
        return Int((min(1, max(0, progress)) * CGFloat(notes.count - 1)).rounded())
    }

    private func registerPassedNote(at progress: CGFloat) {
        let index = noteIndex(for: progress)
        guard index != hapticNoteIndex else { return }
        hapticNoteIndex = index
    }

    private func startNewNote() {
        swipedNoteID = nil
        let note = Note(text: "")
        modelContext.insert(note)
        persist()
        pendingFocusID = note.persistentModelID
    }

    private func endEditing() {
        focusedNoteID = nil
        swipedNoteID = nil
        persist()
    }

    private func persist() {
        try? modelContext.save()
    }

    private func deleteNote(_ note: Note) {
        if focusedNoteID == note.persistentModelID {
            focusedNoteID = nil
        }
        if swipedNoteID == note.persistentModelID {
            swipedNoteID = nil
        }
        modelContext.delete(note)
        persist()
    }
}

private struct NoteRow: View {
    @Bindable var note: Note
    @FocusState.Binding var focusedNoteID: PersistentIdentifier?
    @Binding var pendingFocusID: PersistentIdentifier?
    @Binding var swipedNoteID: PersistentIdentifier?
    var onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var swipeOffset: CGFloat = 0

    private var isFocused: Bool {
        focusedNoteID == note.persistentModelID
    }

    private var isSwipedOpen: Bool {
        swipedNoteID == note.persistentModelID
    }

    private var isThisNoteSwiping: Bool {
        abs(swipeOffset) > 1
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            swipeActions
                .zIndex(0)

            noteContent
                .padding(.vertical, 22)
                .padding(.trailing, 8)
                .background {
                    if isThisNoteSwiping {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(noteBackground)
                    } else {
                        Color(.systemBackground)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: isThisNoteSwiping ? 16 : 0, style: .continuous))
                .zIndex(1)
                .offset(x: swipeOffset)
                .gesture(isFocused ? nil : swipeGesture)
        }
        .onAppear {
            focusIfPending()
            swipeOffset = isSwipedOpen ? -NoteSwipeMetrics.openDistance : 0
        }
        .onChange(of: pendingFocusID) {
            focusIfPending()
        }
        .onChange(of: focusedNoteID) { _, newValue in
            if newValue != note.persistentModelID {
                try? note.modelContext?.save()
            }
            if newValue != nil {
                closeSwipe()
            }
        }
        .onChange(of: isSwipedOpen) { _, open in
            withAnimation(NoteSwipeMetrics.spring) {
                swipeOffset = open ? -NoteSwipeMetrics.openDistance : 0
            }
        }
    }

    private var noteBackground: Color {
        guard isThisNoteSwiping else { return Color(.systemBackground) }
        return colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color(white: 0.96)
    }

    private var noteContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $note.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
                .focused($focusedNoteID, equals: note.persistentModelID)
                .lineLimit(isFocused ? 50 : 8)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)

            Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var swipeActions: some View {
        HStack(spacing: NoteSwipeMetrics.buttonSpacing) {
            swipeButton(systemName: "doc.on.doc", color: Color(white: 0.56)) {
                UIPasteboard.general.string = note.text
                closeSwipe()
            }

            swipeButton(systemName: "trash.fill", color: .red) {
                onDelete()
            }
        }
        .padding(.trailing, 2)
        .opacity(min(1, abs(swipeOffset) / 56.0))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }

                if swipedNoteID != note.persistentModelID {
                    swipedNoteID = nil
                }

                let base = isSwipedOpen ? -NoteSwipeMetrics.openDistance : 0
                swipeOffset = min(0, max(-NoteSwipeMetrics.openDistance - 28, base + horizontal))
            }
            .onEnded { _ in
                let shouldOpen = swipeOffset < -(NoteSwipeMetrics.openDistance * 0.35)
                withAnimation(NoteSwipeMetrics.spring) {
                    if shouldOpen {
                        swipeOffset = -NoteSwipeMetrics.openDistance
                        swipedNoteID = note.persistentModelID
                        focusedNoteID = nil
                    } else {
                        closeSwipe()
                    }
                }
            }
    }

    private func swipeButton(systemName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: NoteSwipeMetrics.buttonSize, height: NoteSwipeMetrics.buttonSize)
                .background(color, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName == "trash.fill" ? "Delete" : "Copy")
    }

    private func closeSwipe() {
        swipedNoteID = nil
        withAnimation(NoteSwipeMetrics.spring) {
            swipeOffset = 0
        }
    }

    private func focusIfPending() {
        guard pendingFocusID == note.persistentModelID else { return }
        focusedNoteID = note.persistentModelID
        pendingFocusID = nil
    }
}

private enum NoteSwipeMetrics {
    static let buttonSize: CGFloat = 40
    static let buttonSpacing: CGFloat = 14
    static let openDistance: CGFloat = 132
    static let spring = Animation.spring(duration: 0.34, bounce: 0.12)
}

private enum TimelineAnchor: Hashable {
    case top
}

private struct TimelineScrollState: Equatable {
    var offsetY: CGFloat
    var progress: CGFloat
    var canScroll: Bool

    var containerHeight: CGFloat

    init(geometry: ScrollGeometry) {
        let visibleHeight = geometry.visibleRect.height
        let scrollable = geometry.contentSize.height - visibleHeight
        offsetY = geometry.visibleRect.minY
        containerHeight = geometry.containerSize.height
        canScroll = scrollable > 24
        progress = scrollable > 1 ? min(1, max(0, offsetY / scrollable)) : 0
    }
}

#Preview("Timeline") {
    let container = try! ModelContainer(
        for: Note.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    context.insert(Note(text: "A quiet thought I wanted to keep."))
    context.insert(
        Note(
            text: "Earlier in the day, something else felt worth writing down.",
            createdAt: .now.addingTimeInterval(-3_600)
        )
    )

    return TimelineView()
        .modelContainer(container)
}

#Preview("Time Rail") {
    let container = try! ModelContainer(
        for: Note.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let samples = [
        "A quiet thought I wanted to keep.",
        "Something I noticed on a walk.",
        "A sentence I did not want to lose.",
        "Later, the same idea returned in a different shape."
    ]

    for index in 0..<120 {
        context.insert(
            Note(
                text: samples[index % samples.count],
                createdAt: .now.addingTimeInterval(Double(-index) * 86_400 * 6)
            )
        )
    }

    return TimelineView()
        .modelContainer(container)
}
