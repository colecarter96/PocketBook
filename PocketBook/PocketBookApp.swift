//
//  PocketBookApp.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI
import UIKit

@main
struct PocketBookApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Note.self, Board.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

@Observable
final class RecentDelete {
    private(set) var snapshot: Snapshot?

    struct Snapshot {
        var text: String
        var createdAt: Date
        var boards: [Board]
        var audioFileName: String?
        var audioDuration: Double
        var imageFileNames: [String]
        var revisitDone: Bool
        var revisitAfter: Date?
    }

    var canUndo: Bool { snapshot != nil }

    func remember(_ note: Note) {
        if let previous = snapshot {
            if previous.audioFileName != note.audioFileName {
                VoiceMemoStore.delete(previous.audioFileName)
            }
            for name in previous.imageFileNames {
                NoteImageStore.delete(name)
            }
        }
        snapshot = Snapshot(
            text: note.text,
            createdAt: note.createdAt,
            boards: note.boards,
            audioFileName: note.audioFileName,
            audioDuration: note.audioDuration,
            imageFileNames: note.imageFileNames,
            revisitDone: note.revisitDone,
            revisitAfter: note.revisitAfter
        )
    }

    func undo(in context: ModelContext) {
        guard let snapshot else { return }
        let note = Note(text: snapshot.text, createdAt: snapshot.createdAt)
        context.insert(note)
        note.boards = snapshot.boards
        note.audioFileName = snapshot.audioFileName
        note.audioDuration = snapshot.audioDuration
        note.imageFileNames = snapshot.imageFileNames
        note.revisitDone = snapshot.revisitDone
        note.revisitAfter = snapshot.revisitAfter
        try? context.save()
        self.snapshot = nil
    }
}

enum PocketTab: Hashable {
    case timeline
    case search
    case revisit
    case boards
}

private struct PocketNavHiddenKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var pocketNavHidden: Binding<Bool> {
        get { self[PocketNavHiddenKey.self] }
        set { self[PocketNavHiddenKey.self] = newValue }
    }
}

struct RootView: View {
    @State private var recentDelete = RecentDelete()
    @State private var voiceMemos = VoiceMemoController()
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: PocketTab = .timeline
    @State private var timelineTopToken = 0
    @State private var searchBarOpen = false
    @State private var searchQuery = ""
    @State private var recentSearches = RecentSearches.load()
    @State private var keyboardOverlap: CGFloat = 0
    @State private var hidesNav = false
    @FocusState private var searchFieldFocused: Bool

    init() {
        _ = InstantTabSwitch.disable
    }

    private var navDropsBehindKeyboard: Bool {
        keyboardOverlap > 0 && !searchFieldFocused
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab.animation(nil)) {
                Tab("Timeline", systemImage: "house", value: PocketTab.timeline) {
                    TimelineView(scrollToTopToken: timelineTopToken)
                }

                Tab("Search", systemImage: "magnifyingglass", value: PocketTab.search) {
                    SearchView(
                        query: $searchQuery,
                        isFieldFocused: searchFieldFocused,
                        recents: recentSearches,
                        onPickRecent: pickRecent,
                        onOpenNote: dismissSearchKeyboard
                    )
                }

                Tab("Revisit", systemImage: "arrow.clockwise", value: PocketTab.revisit) {
                    RevisitView()
                }

                Tab("Boards", systemImage: "square.stack", value: PocketTab.boards) {
                    BoardsView()
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .tint(.primary)
            .animation(nil, value: selectedTab)

            StreamNavBar(
                selectedTab: selectedTab,
                searchBarOpen: searchBarOpen,
                query: $searchQuery,
                isSearchFocused: $searchFieldFocused,
                onSelect: selectTab,
                onSubmit: commitSearch,
                onCloseSearch: closeSearch
            )
            .padding(.bottom, navDropsBehindKeyboard ? 0 : 8)
            .offset(y: navDropsBehindKeyboard ? keyboardOverlap : 0)
            .opacity(hidesNav ? 0 : 1)
            .allowsHitTesting(!hidesNav && !navDropsBehindKeyboard)
        }
        .environment(\.pocketNavHidden, $hidesNav)
        .environment(recentDelete)
        .environment(voiceMemos)
        .task {
            let notes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
            var keptAudio = Set(notes.compactMap(\.audioFileName))
            if let pending = recentDelete.snapshot?.audioFileName {
                keptAudio.insert(pending)
            }
            VoiceMemoStore.deleteAll(except: keptAudio)

            var keptImages = Set(notes.flatMap(\.imageFileNames))
            if let pending = recentDelete.snapshot?.imageFileNames {
                keptImages.formUnion(pending)
            }
            NoteImageStore.deleteAll(except: keptImages)
        }
        .onChange(of: searchFieldFocused) { _, focused in
            if !focused {
                commitSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = (note.object as? UIView)?.window?.windowScene?.screen.bounds.height
                ?? UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
                    .first
                ?? frame.maxY
            let overlap = max(0, screenHeight - frame.minY)
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeInOut(duration: duration)) {
                keyboardOverlap = overlap
            }
        }
    }

    private func selectTab(_ tab: PocketTab) {
        if tab == .timeline, selectedTab == .timeline {
            timelineTopToken += 1
            return
        }
        if tab != .search {
            searchFieldFocused = false
        }
        withAnimation(.easeOut(duration: 0.22)) {
            searchBarOpen = tab == .search
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
        }
    }

    private func commitSearch() {
        RecentSearches.remember(searchQuery, into: &recentSearches)
    }

    private func pickRecent(_ term: String) {
        searchQuery = term
        searchFieldFocused = false
        RecentSearches.remember(term, into: &recentSearches)
    }

    private func dismissSearchKeyboard() {
        searchFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func closeSearch() {
        dismissSearchKeyboard()
        withAnimation(.easeOut(duration: 0.22)) {
            searchBarOpen = false
        }
    }
}

private enum InstantTabSwitch {
    static let disable: Void = {
        let cls: AnyClass = UITabBarController.self
        exchange(
            cls,
            #selector(setter: UITabBarController.selectedViewController),
            #selector(UITabBarController.pocket_setSelectedViewController(_:))
        )
        exchange(
            cls,
            #selector(setter: UITabBarController.selectedIndex),
            #selector(UITabBarController.pocket_setSelectedIndex(_:))
        )
    }()

    private static func exchange(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let method = class_getInstanceMethod(cls, original),
              let swizzled = class_getInstanceMethod(cls, replacement) else { return }
        method_exchangeImplementations(method, swizzled)
    }
}

extension UITabBarController {
    @objc func pocket_setSelectedViewController(_ viewController: UIViewController?) {
        UIView.performWithoutAnimation {
            pocket_setSelectedViewController(viewController)
        }
    }

    @objc func pocket_setSelectedIndex(_ index: Int) {
        UIView.performWithoutAnimation {
            pocket_setSelectedIndex(index)
        }
    }
}

