//
//  PocketNav.swift
//  PocketBook
//

import SwiftUI
import UIKit

enum RecentSearches {
    private static let key = "pocketbook.recentSearches"
    static let limit = 6

    static func load() -> [String] {
        Array((UserDefaults.standard.stringArray(forKey: key) ?? []).prefix(limit))
    }

    static func remember(_ query: String, into recents: inout [String]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recents.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recents.insert(trimmed, at: 0)
        if recents.count > limit {
            recents = Array(recents.prefix(limit))
        }
        UserDefaults.standard.set(recents, forKey: key)
    }
}

enum PocketBarClearance {
    /// Extra space above the custom bar. The system tab bar already insets its content.
    static var control: CGFloat { if #available(iOS 26.0, *) { 16 } else { 78 } }
    static var scroll: CGFloat { if #available(iOS 26.0, *) { 16 } else { 88 } }
    static var rail: CGFloat { if #available(iOS 26.0, *) { 16 } else { 96 } }
    static var tray: CGFloat { if #available(iOS 26.0, *) { 12 } else { 108 } }
    static var revisitGrid: CGFloat { if #available(iOS 26.0, *) { 124 } else { 220 } }
}

struct StreamNavBar: View {
    var selectedTab: PocketTab
    var onSelect: (PocketTab) -> Void

    var body: some View {
        tabs
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .contentShape(Capsule())
            .padding(.horizontal, 28)
            .animation(nil, value: selectedTab)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tab(.timeline, systemImage: "list.bullet", title: "Timeline")
            tab(.search, systemImage: "magnifyingglass", title: "Search")
            tab(.revisit, systemImage: "square.stack", title: "Revisit")
            tab(.boards, systemImage: "square.grid.2x2", title: "Lists")
        }
    }

    private func tab(_ tab: PocketTab, systemImage: String, title: String) -> some View {
        let selected = selectedTab == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Capsule(style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
