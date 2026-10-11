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
    var searchBarOpen: Bool
    @Binding var query: String
    var isSearchFocused: FocusState<Bool>.Binding
    var onSelect: (PocketTab) -> Void
    var onSubmit: () -> Void
    var onCloseSearch: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if isSearchFocused.wrappedValue {
                Button(action: onCloseSearch) {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(Color.red, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel("Close Search")
                .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 10) {
                blob(.timeline, systemImage: "house", title: "Timeline")

                if searchBarOpen {
                    searchBar
                } else {
                    blob(.search, systemImage: "magnifyingglass", title: "Search")
                }

                blob(.revisit, systemImage: "arrow.clockwise", title: "Revisit")
                blob(.boards, systemImage: "square.stack", title: "Boards")
            }
            .padding(.horizontal, searchBarOpen ? 16 : 0)
            .frame(maxWidth: searchBarOpen ? 560 : nil)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.22), value: searchBarOpen)
        .animation(.easeOut(duration: 0.18), value: isSearchFocused.wrappedValue)
    }

    private func blob(_ tab: PocketTab, systemImage: String, title: String) -> some View {
        let selected = selectedTab == tab && !searchBarOpen
        return Button {
            onSelect(tab)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.black)
                .frame(width: 54, height: 54)
                .background(selected ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(selected ? 0 : 0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.black.opacity(0.9))

            TextField(
                "",
                text: $query,
                prompt: Text("Search Stream").foregroundStyle(Color.black.opacity(0.9))
            )
            .font(.system(.body, design: .serif))
            .foregroundStyle(Color.black)
            .tint(Color.black)
            .focused(isSearchFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit(onSubmit)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if !isSearchFocused.wrappedValue {
                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onTapGesture(perform: focusSearch)
            }
        }
        .overlay(alignment: .trailing) {
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel("Clear")
            }
        }
        .environment(\.colorScheme, .light)
    }

    private func focusSearch() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isSearchFocused.wrappedValue = true
        }
    }
}
