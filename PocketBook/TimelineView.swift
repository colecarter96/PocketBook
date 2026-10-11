//
//  TimelineView.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI
import PhotosUI
import UIKit

struct TimelineView: View {
    var scrollToTopToken = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RecentDelete.self) private var recentDelete
    @Environment(VoiceMemoController.self) private var voiceMemos
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    @State private var editor = TimelineEditor()
    @State private var railProgress: CGFloat = 0
    @State private var railDate: Date?
    @State private var isDraggingRail = false
    @State private var canScrollTimeline = false
    @State private var timelineHeight: CGFloat = 0
    @State private var restingTimelineHeight: CGFloat = 0
    @State private var hapticNoteIndex = 0
    @State private var railImpactToken = 0
    @State private var noteFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var radialNoteID: PersistentIdentifier?
    @State private var radialOrigin: CGPoint?
    @State private var radialFinger: CGPoint?
    @State private var radialActions: [NotePressAction] = []
    @State private var hoveredAction: NotePressAction?
    @State private var pressedScale: CGFloat = 1
    @State private var dimFrame: CGRect = .zero
    @State private var menuBounds: CGRect = .zero
    @State private var boardPickerNote: Note?
    @State private var libraryNote: Note?
    @State private var showLibrary = false
    @State private var cameraNote: Note?
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var previewImageName: String?
    @State private var editingPhotosNoteID: PersistentIdentifier?
    @State private var headerHidden: CGFloat = 0
    @State private var statusBarHeight: CGFloat = 54

    private var isEditing: Bool { editor.editingID != nil }
    private var canUseRail: Bool {
        notes.count >= 8 && canScrollTimeline && radialNoteID == nil
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
            .toolbar(.hidden, for: .tabBar)
            .toolbarColorScheme(headerHidden < statusBarHeight ? .dark : .light, for: .navigationBar)
            .overlay(alignment: .top) {
                streamHeader
                    .offset(y: streamHeaderSlide)
                    .ignoresSafeArea(edges: .top)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { statusBarHeight = resolvedStatusBarHeight(geometry.safeAreaInsets.top) }
                        .onChange(of: geometry.safeAreaInsets.top) { _, inset in
                            statusBarHeight = resolvedStatusBarHeight(inset)
                        }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 14) {
                    if recentDelete.canUndo {
                        Button {
                            recentDelete.undo(in: modelContext)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.gray.opacity(0.55))
                        }
                        .accessibilityLabel("Undo Delete")
                    }

                    if !isEditing {
                        composeButton
                    }
                }
                .padding(.trailing, 30)
                .padding(.bottom, 78)
            }
            .scrollDismissesKeyboard(.never)
            .photosPicker(
                isPresented: $showLibrary,
                selection: $libraryItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: showLibrary) { _, isShowing in
                guard !isShowing, let note = libraryNote else { return }
                let picked = libraryItems
                libraryNote = nil
                guard !picked.isEmpty else {
                    libraryItems = []
                    return
                }
                Task {
                    await NoteImageStore.importPhotos(picked, into: note)
                    libraryItems = []
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { cameraNote != nil },
                    set: { if !$0 { cameraNote = nil } }
                )
            ) {
                CameraPicker { image in
                    if let image, let note = cameraNote {
                        NoteImageStore.append(image, to: note)
                        try? note.modelContext?.save()
                    }
                    cameraNote = nil
                }
                .ignoresSafeArea()
            }
            .overlay {
                if let previewImageName {
                    NoteImagePreview(fileName: previewImageName) {
                        self.previewImageName = nil
                    }
                }
            }
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

    private var streamHeaderSlide: CGFloat {
        -headerHidden
    }

    private var streamHeaderReach: CGFloat {
        statusBarHeight + StreamHeader.height
    }

    private var streamHeader: some View {
        VStack(spacing: 0) {
            Color.black
                .frame(height: statusBarHeight)

            HStack(alignment: .center) {
                Text("Stream")
                    .font(.custom("HelveticaNeue-Medium", size: 22))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Menu {
                    Button("New Note", systemImage: "plus") {
                        startNewNote()
                    }
                } label: {
                    Text("---")
                        .font(.custom("HelveticaNeue-Medium", size: 18))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Menu")
            }
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .frame(height: StreamHeader.height)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func resolvedStatusBarHeight(_ inset: CGFloat) -> CGFloat {
        if inset > 1 { return inset }
        let bar = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.statusBarManager?.statusBarFrame.height }
            .first ?? 54
        return bar > 1 ? bar : 54
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
                Color.clear
                .frame(height: StreamHeader.height + 32)
                .id(TimelineAnchor.top)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                ForEach(notes) { note in
                    NoteRow(
                        note: note,
                        isEditing: editor.editingID == note.persistentModelID,
                        editor: editor,
                        onTap: { edit(note) },
                        onLongPress: { state, point in
                            handlePress(state, at: point, noteID: note.persistentModelID)
                        },
                        onLibrary: {
                            libraryNote = note
                            libraryItems = []
                            showLibrary = true
                        },
                        onCamera: { cameraNote = note },
                        onOpenImage: { previewImageName = $0 },
                        isArrangingPhotos: editingPhotosNoteID == note.persistentModelID,
                        onDeleteImage: { removeImage($0, from: note) },
                        onFinishPhotoEdit: { editingPhotosNoteID = nil }
                    )
                    .id(note.persistentModelID)
                    .scaleEffect(radialNoteID == note.persistentModelID ? pressedScale : 1)
                    .rotation3DEffect(
                        .degrees(tilt(for: note).x),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.45
                    )
                    .rotation3DEffect(
                        .degrees(tilt(for: note).y),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.45
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: NoteFramePreference.self,
                                value: [note.persistentModelID: geometry.frame(in: .global)]
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets(
                        top: 2,
                        leading: 28,
                        bottom: 2,
                        trailing: 36
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(.systemBackground))
                }

                Color.clear
                    .frame(minHeight: 240)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .onScrollGeometryChange(for: TimelineScrollState.self) { geometry in
                TimelineScrollState(geometry: geometry)
            } action: { oldState, newState in
                canScrollTimeline = newState.canScroll
                updateStreamHeader(from: oldState.offsetY, to: newState.offsetY)
                if editor.editingID == nil {
                    timelineHeight = newState.containerHeight
                    restingTimelineHeight = newState.containerHeight
                }
                guard !isDraggingRail else { return }
                railProgress = newState.progress
                registerPassedNote(at: newState.progress)
            }
            .overlay(alignment: .trailing) {
                if canUseRail {
                    GeometryReader { geometry in
                        let railSpan = max(geometry.size.height - 28 - 96, 1)
                        let topCut = railSpan * (1 - 0.85 * 0.85)
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
                        .padding(.top, 28 + topCut)
                        .padding(.bottom, 96)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .opacity(isEditing ? 0 : 1)
                        .allowsHitTesting(!isEditing)
                    }
                }
            }
            .overlay {
                NoteDimOverlay(noteFrame: dimNoteFrame)
                    .opacity(radialNoteID == nil ? 0 : 1)
                    .animation(.easeInOut(duration: 0.28), value: radialNoteID == nil)
                    .allowsHitTesting(false)
            }
            .overlay {
                if let radialOrigin {
                    RadialActionMenu(
                        origin: radialOrigin,
                        actions: radialActions,
                        hovered: hoveredAction,
                        container: menuBounds
                    )
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: scrollToTopToken) { _, _ in
                if radialNoteID != nil {
                    cancelRadial()
                }
                editor.end()
                withAnimation(.spring(duration: 0.95, bounce: 0)) {
                    proxy.scrollTo(TimelineAnchor.top, anchor: .top)
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MenuBoundsPreference.self,
                        value: geometry.frame(in: .global)
                    )
                }
            }
            .onPreferenceChange(MenuBoundsPreference.self) { menuBounds = $0 }
            .onPreferenceChange(NoteFramePreference.self) { frames in
                noteFrames = frames
                if let radialNoteID, let frame = frames[radialNoteID] {
                    dimFrame = frame
                }
            }
            .sheet(item: $boardPickerNote) { note in
                BoardPickerSheet(note: note)
            }
        }
    }

    private func handlePress(
        _ state: UIGestureRecognizer.State,
        at point: CGPoint,
        noteID: PersistentIdentifier
    ) -> Bool {
        switch state {
        case .began:
            guard !isEditing else { return false }
            beginRadial(noteID: noteID, at: point)
            return true
        case .changed:
            guard radialNoteID != nil, let radialOrigin else { return false }
            radialFinger = point
            let next = action(at: point, origin: radialOrigin)
            if next != hoveredAction {
                hoveredAction = next
                if next != nil {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            return true
        case .ended:
            let wasChoosing = radialNoteID != nil
            finishRadial()
            if wasChoosing {
                editor.end()
            }
            return true
        case .cancelled, .failed:
            if radialNoteID != nil {
                cancelRadial()
            }
            return true
        default:
            return radialNoteID != nil
        }
    }

    private func edit(_ note: Note) {
        guard radialNoteID == nil else { return }
        let isNewest = notes.first?.persistentModelID == note.persistentModelID
        editor.begin(note.persistentModelID, scrollIntoView: !isNewest)
    }

    private var dimNoteFrame: CGRect {
        if let radialNoteID, let frame = noteFrames[radialNoteID], frame.width > 1 {
            return frame
        }
        return dimFrame
    }

    private func beginRadial(noteID: PersistentIdentifier, at point: CGPoint) {
        editor.end()
        if let frame = noteFrames[noteID] {
            dimFrame = frame
        }
        radialNoteID = noteID
        radialActions = menuActions(for: noteID)
        radialOrigin = point
        radialFinger = point
        hoveredAction = nil
        pressedScale = 0.9
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.1)) {
            pressedScale = 0.9
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            guard radialNoteID == noteID else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                pressedScale = 1.08
            }
        }
    }

    private func finishRadial() {
        let action = hoveredAction
        let noteID = radialNoteID
        cancelRadial()
        guard let action, let noteID, let note = notes.first(where: { $0.persistentModelID == noteID }) else { return }
        switch action {
        case .copy:
            UIPasteboard.general.string = note.text
        case .board:
            boardPickerNote = note
        case .memo:
            removeMemo(from: note)
        case .photos:
            editingPhotosNoteID = note.persistentModelID
        case .delete:
            deleteNote(note)
        }
    }

    private func cancelRadial() {
        if let radialNoteID, let frame = noteFrames[radialNoteID] {
            dimFrame = frame
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            pressedScale = 1
        }
        radialNoteID = nil
        radialActions = []
        radialOrigin = nil
        radialFinger = nil
        hoveredAction = nil
    }

    private func action(at point: CGPoint, origin: CGPoint) -> NotePressAction? {
        let bounds = menuBounds.width > 1 ? menuBounds : UIScreen.main.bounds
        let centers = RadialFan.placement(origin: origin, actions: radialActions, in: bounds).centers
        var nearest: (action: NotePressAction, distance: CGFloat)?
        for action in radialActions {
            guard let center = centers[action] else { continue }
            let distance = hypot(point.x - center.x, point.y - center.y)
            guard distance < 36 else { continue }
            if nearest == nil || distance < nearest!.distance {
                nearest = (action, distance)
            }
        }
        return nearest?.action
    }

    private func menuActions(for noteID: PersistentIdentifier) -> [NotePressAction] {
        guard let note = notes.first(where: { $0.persistentModelID == noteID }) else {
            return [.copy, .board, .delete]
        }
        var actions: [NotePressAction] = [.copy]
        if note.audioFileName != nil {
            actions.append(.memo)
        }
        actions.append(.board)
        if !note.imageFileNames.isEmpty {
            actions.append(.photos)
        }
        actions.append(.delete)
        return actions
    }

    private func removeMemo(from note: Note) {
        voiceMemos.stopPlayback(of: note)
        VoiceMemoStore.delete(note.audioFileName)
        note.audioFileName = nil
        note.audioDuration = 0
        note.transcript = ""
        persist()
    }

    private func removeImage(_ fileName: String, from note: Note) {
        var names = note.imageFileNames
        names.removeAll { $0 == fileName }
        note.imageFileNames = names
        NoteImageStore.delete(fileName)
        persist()
        if names.isEmpty {
            editingPhotosNoteID = nil
        }
    }

    private func tilt(for note: Note) -> (x: Double, y: Double) {
        guard radialNoteID == note.persistentModelID,
              let finger = radialFinger,
              let frame = noteFrames[note.persistentModelID] else {
            return (0, 0)
        }
        let dx = (finger.x - frame.midX) / max(frame.width, 1)
        let dy = (finger.y - frame.midY) / max(frame.height, 1)
        return (
            x: Double(max(-14, min(14, -dy * 22))),
            y: Double(max(-18, min(18, dx * 28)))
        )
    }

    private func scrub(to progress: CGFloat, proxy: ScrollViewProxy) {
        guard !notes.isEmpty else { return }

        if !isDraggingRail, editor.editingID == nil {
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

    private func updateStreamHeader(from oldOffset: CGFloat, to newOffset: CGFloat) {
        if newOffset <= 0 {
            headerHidden = 0
            return
        }
        let delta = newOffset - oldOffset
        headerHidden = min(streamHeaderReach, max(0, headerHidden + delta))
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
        let note = Note(text: "")
        modelContext.insert(note)
        persist()
        editor.begin(note.persistentModelID, scrollIntoView: false)
    }

    private func persist() {
        try? modelContext.save()
    }

    private func deleteNote(_ note: Note) {
        if editor.editingID == note.persistentModelID {
            editor.end()
        }
        recentDelete.remember(note)
        modelContext.delete(note)
        persist()
    }
}

private struct MenuBoundsPreference: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct NoteFramePreference: PreferenceKey {
    static var defaultValue: [PersistentIdentifier: CGRect] = [:]

    static func reduce(
        value: inout [PersistentIdentifier: CGRect],
        nextValue: () -> [PersistentIdentifier: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct NoteDimOverlay: View {
    var noteFrame: CGRect

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global)
            let hole = CGRect(
                x: noteFrame.minX - origin.minX,
                y: noteFrame.minY - origin.minY,
                width: noteFrame.width,
                height: noteFrame.height
            )

            Color.black.opacity(0.42)
                .mask {
                    ZStack {
                        Rectangle()
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .frame(width: hole.width + 12, height: hole.height + 6)
                            .position(x: hole.midX, y: hole.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
        }
        .ignoresSafeArea()
    }
}

private struct NoteRow: View {
    @Bindable var note: Note
    var isEditing: Bool
    var editor: TimelineEditor
    var onTap: () -> Void
    var onLongPress: (UIGestureRecognizer.State, CGPoint) -> Bool
    var onLibrary: () -> Void
    var onCamera: () -> Void
    var onOpenImage: (String) -> Void
    var isArrangingPhotos: Bool
    var onDeleteImage: (String) -> Void
    var onFinishPhotoEdit: () -> Void
    @Environment(VoiceMemoController.self) private var voice
    @State private var editorHeight: CGFloat = 22
    @State private var hitFrames = NoteHitFrames()
    @State private var transcriptOpen = false
    @State private var transcriptEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                NoteTextView(note: note, editor: editor, onHeight: { height in
                    if abs(editorHeight - height) > 0.5 {
                        editorHeight = height
                    }
                }, onLibrary: onLibrary, onCamera: onCamera)
                .frame(maxWidth: .infinity, minHeight: editorHeight, alignment: .topLeading)
            } else {
                Text(note.text.isEmpty ? " " : note.text)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(note.text.isEmpty ? .clear : .primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(note.audioFileName == nil ? 8 : 4)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
            }

            VoiceMemoBar(note: note)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: NoteHitPreference.self,
                            value: NoteHitFrames(memo: geometry.frame(in: .global))
                        )
                    }
                }
            if note.audioFileName != nil {
                MemoTranscript(note: note, isOpen: $transcriptOpen, isEditing: $transcriptEditing)
            }
            NoteImageStrip(
                fileNames: note.imageFileNames,
                isArranging: isArrangingPhotos,
                onOpen: onOpenImage
            )

            Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if !isEditing {
                NoteTouchSurface(
                    passThrough: transcriptEditing ? hitFrames.transcriptField : .zero,
                    onTap: handleCardTap,
                    onLongPress: onLongPress
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onPreferenceChange(NoteHitPreference.self) { hitFrames = $0 }
        .onChange(of: isEditing) { _, editing in
            if editing {
                transcriptEditing = false
            }
        }
    }

    private func handleCardTap(_ point: CGPoint) {
        if isArrangingPhotos, hitFrames.check.insetBy(dx: -8, dy: -8).contains(point) {
            onFinishPhotoEdit()
            return
        }
        if isArrangingPhotos {
            for (fileName, frame) in hitFrames.images {
                let center = CGPoint(x: frame.maxX - 15, y: frame.minY + 15)
                if hypot(point.x - center.x, point.y - center.y) < 22 {
                    onDeleteImage(fileName)
                    return
                }
            }
        }
        if let fileName = hitFrames.images.first(where: { $0.value.insetBy(dx: -6, dy: -6).contains(point) })?.key {
            onOpenImage(fileName)
            return
        }
        if transcriptOpen, hitFrames.transcriptField.insetBy(dx: -4, dy: -4).contains(point) {
            transcriptEditing = true
            return
        }
        if hitFrames.transcriptToggle.insetBy(dx: -8, dy: -6).contains(point) {
            withAnimation(.easeOut(duration: 0.2)) {
                transcriptOpen.toggle()
            }
            return
        }
        if note.audioFileName != nil, hitFrames.memo.insetBy(dx: -6, dy: -6).contains(point) {
            voice.togglePlayback(for: note)
            return
        }
        onTap()
    }
}

private enum StreamHeader {
    static let height: CGFloat = 48
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
        for: Note.self, Board.self,
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
        .environment(RecentDelete())
        .environment(VoiceMemoController())
}

#Preview("Time Rail") {
    let container = try! ModelContainer(
        for: Note.self, Board.self,
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
        .environment(RecentDelete())
        .environment(VoiceMemoController())
}
