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
    }

    var canUndo: Bool { snapshot != nil }

    func remember(_ note: Note) {
        snapshot = Snapshot(text: note.text, createdAt: note.createdAt, boards: note.boards)
    }

    func undo(in context: ModelContext) {
        guard let snapshot else { return }
        let note = Note(text: snapshot.text, createdAt: snapshot.createdAt)
        context.insert(note)
        note.boards = snapshot.boards
        try? context.save()
        self.snapshot = nil
    }
}

enum PocketTab: Hashable {
    case timeline
    case search
    case boards
}

struct RootView: View {
    @State private var recentDelete = RecentDelete()
    @State private var selectedTab: PocketTab = .timeline
    @State private var searchFocusToken = 0
    @State private var timelineTopToken = 0

    init() {
        _ = InstantTabSwitch.disable
    }

    var body: some View {
        TabView(selection: $selectedTab.animation(nil)) {
            Tab("Timeline", systemImage: "house", value: PocketTab.timeline) {
                TimelineView(scrollToTopToken: timelineTopToken)
            }

            Tab("Search", systemImage: "magnifyingglass", value: PocketTab.search) {
                SearchView(
                    isSelected: selectedTab == .search,
                    focusToken: searchFocusToken
                )
            }

            Tab("Boards", systemImage: "square.stack", value: PocketTab.boards) {
                BoardsView()
            }
        }
        .tint(.primary)
        .animation(nil, value: selectedTab)
        .environment(recentDelete)
        .background {
            SearchTabTapCatcher(
                onSearchTap: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        selectedTab = .search
                        searchFocusToken += 1
                    }
                },
                onTimelineReselect: {
                    guard selectedTab == .timeline else { return }
                    timelineTopToken += 1
                }
            )
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

private struct SearchTabTapCatcher: UIViewControllerRepresentable {
    var onSearchTap: () -> Void
    var onTimelineReselect: () -> Void

    func makeUIViewController(context: Context) -> Catcher {
        let catcher = Catcher()
        catcher.onSearchTap = onSearchTap
        catcher.onTimelineReselect = onTimelineReselect
        return catcher
    }

    func updateUIViewController(_ catcher: Catcher, context: Context) {
        catcher.onSearchTap = onSearchTap
        catcher.onTimelineReselect = onTimelineReselect
        catcher.attachIfNeeded()
    }

    final class Catcher: UIViewController, UIGestureRecognizerDelegate {
        var onSearchTap: () -> Void = {}
        var onTimelineReselect: () -> Void = {}
        private weak var hookedTabBar: UITabBar?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachIfNeeded()
        }

        func attachIfNeeded() {
            DispatchQueue.main.async { [weak self] in
                self?.hookTabBar()
            }
        }

        private func hookTabBar() {
            guard let tabBar = tabBarController?.tabBar, hookedTabBar !== tabBar else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tabBarTapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            tabBar.addGestureRecognizer(tap)
            hookedTabBar = tabBar
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func tabBarTapped(_ gesture: UITapGestureRecognizer) {
            guard let tabBar = hookedTabBar, gesture.state == .began else { return }
            let point = gesture.location(in: tabBar)
            let buttons = tabBar.subviews
                .filter { $0 is UIControl && $0.bounds.width > 24 }
                .sorted { $0.frame.minX < $1.frame.minX }
            let hitSearch = buttons.count >= 2
                ? buttons[1].frame.contains(point)
                : point.x > tabBar.bounds.width / 3 && point.x < tabBar.bounds.width * 2 / 3
            let hitTimeline = buttons.count >= 1
                ? buttons[0].frame.contains(point)
                : point.x < tabBar.bounds.width / 3
            if hitSearch {
                onSearchTap()
            } else if hitTimeline {
                onTimelineReselect()
            }
        }
    }
}
