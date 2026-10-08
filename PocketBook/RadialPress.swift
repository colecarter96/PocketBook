//
//  RadialPress.swift
//  PocketBook
//

import SwiftUI
import UIKit

enum NotePressAction: CaseIterable, Equatable {
    case copy
    case board
    case delete

    var title: String {
        switch self {
        case .copy: "Copy"
        case .board: "Board"
        case .delete: "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: "doc.on.doc"
        case .board: "square.stack"
        case .delete: "trash"
        }
    }

    func offset(belowFinger: Bool) -> CGSize {
        let lift: CGFloat = belowFinger ? 1 : -1
        switch self {
        case .copy: return CGSize(width: -76, height: 62 * lift)
        case .board: return CGSize(width: 0, height: 108 * lift)
        case .delete: return CGSize(width: 76, height: 62 * lift)
        }
    }
}

struct RadialActionMenu: View {
    var origin: CGPoint
    var hovered: NotePressAction?

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let localOrigin = CGPoint(x: origin.x - frame.minX, y: origin.y - frame.minY)
            let below = origin.y < 190

            ZStack {
                ForEach(NotePressAction.allCases, id: \.title) { action in
                    let offset = action.offset(belowFinger: below)
                    actionCircle(action, isHovered: hovered == action)
                        .position(
                            x: localOrigin.x + offset.width,
                            y: localOrigin.y + offset.height
                        )
                }

                if let hovered {
                    Text(hovered.title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(.primary)
                        .position(x: localOrigin.x, y: labelY(localOrigin: localOrigin, below: below))
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hovered)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    private func labelY(localOrigin: CGPoint, below: Bool) -> CGFloat {
        below ? localOrigin.y + 168 : localOrigin.y - 168
    }

    private func actionCircle(_ action: NotePressAction, isHovered: Bool) -> some View {
        let size: CGFloat = isHovered ? 68 : 50
        return Image(systemName: action.systemImage)
            .font(.system(size: isHovered ? 20 : 16, weight: .semibold))
            .foregroundStyle(action == .delete && isHovered ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(action == .delete && isHovered ? Color.red : Color(.systemBackground))
                    .shadow(color: .black.opacity(0.18), radius: isHovered ? 16 : 10, y: 4)
            }
    }
}

