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

struct StreamNavBar: View {
    var selectedTab: PocketTab
    var onSelect: (PocketTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            blob(.timeline, systemImage: "house", title: "Timeline")
            blob(.search, systemImage: "magnifyingglass", title: "Search")
            blob(.revisit, systemImage: "arrow.clockwise", title: "Revisit")
            blob(.boards, systemImage: "square.stack", title: "Lists")
        }
        .animation(nil, value: selectedTab)
    }

    private func blob(_ tab: PocketTab, systemImage: String, title: String) -> some View {
        let selected = selectedTab == tab
        return Button {
            onSelect(tab)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.black)
                .frame(width: 46, height: 46)
                .background(selected ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(selected ? 0 : 0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
