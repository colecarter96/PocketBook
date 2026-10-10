//
//  RadialPress.swift
//  PocketBook
//

import SwiftUI
import UIKit

enum NotePressAction: CaseIterable, Hashable {
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
}

struct RadialPlacement: Equatable {
    var centers: [NotePressAction: CGPoint]
    var label: CGPoint
}

enum RadialFan {
    private static let restingRadius: CGFloat = 82
    private static let spread: CGFloat = 0.82
    private static let circleMargin: CGFloat = 40

    static func placement(origin: CGPoint, in container: CGRect) -> RadialPlacement {
        let safe = safeRect(in: container, margin: circleMargin)
        var radius = restingRadius
        var aim = aimAngle(origin: origin, safe: safe, radius: radius)
        while overflow(origin: origin, aim: aim, radius: radius, safe: safe) > 1, radius > 64 {
            radius -= 4
            aim = aimAngle(origin: origin, safe: safe, radius: radius)
        }

        let centers: [NotePressAction: CGPoint] = [
            .copy: point(origin: origin, angle: aim - spread, radius: radius),
            .board: point(origin: origin, angle: aim, radius: radius),
            .delete: point(origin: origin, angle: aim + spread, radius: radius)
        ]
        let rawLabel = point(origin: origin, angle: aim, radius: radius + 52)
        let label = CGPoint(
            x: min(max(rawLabel.x, container.minX + 56), container.maxX - 56),
            y: min(max(rawLabel.y, container.minY + 18), container.maxY - 18)
        )
        return RadialPlacement(centers: centers, label: label)
    }

    private static func aimAngle(origin: CGPoint, safe: CGRect, radius: CGFloat) -> CGFloat {
        let preferred: CGFloat = (origin.y - safe.minY) >= (safe.maxY - origin.y) ? -.pi / 2 : .pi / 2
        if overflow(origin: origin, aim: preferred, radius: radius, safe: safe) <= 1 {
            return preferred
        }

        let step: CGFloat = .pi / 60
        for index in 1...60 {
            let turn = CGFloat(index) * step
            let clockwise = preferred + turn
            let counter = preferred - turn
            let clockwiseOverflow = overflow(origin: origin, aim: clockwise, radius: radius, safe: safe)
            let counterOverflow = overflow(origin: origin, aim: counter, radius: radius, safe: safe)
            if clockwiseOverflow <= 1 { return clockwise }
            if counterOverflow <= 1 { return counter }
        }
        return preferred
    }

    private static func overflow(origin: CGPoint, aim: CGFloat, radius: CGFloat, safe: CGRect) -> CGFloat {
        [-spread, 0, spread].reduce(0) { total, delta in
            let center = point(origin: origin, angle: aim + delta, radius: radius)
            let dx = max(safe.minX - center.x, center.x - safe.maxX, 0)
            let dy = max(safe.minY - center.y, center.y - safe.maxY, 0)
            return total + dx + dy
        }
    }

    private static func point(origin: CGPoint, angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + cos(angle) * radius,
            y: origin.y + sin(angle) * radius
        )
    }

    private static func safeRect(in container: CGRect, margin: CGFloat) -> CGRect {
        var inset = margin
        while inset > 8 {
            let rect = container.insetBy(dx: inset, dy: inset)
            if rect.width > 24, rect.height > 24 { return rect }
            inset -= 6
        }
        return container
    }
}

struct RadialActionMenu: View {
    var origin: CGPoint
    var hovered: NotePressAction?
    var container: CGRect

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let bounds = container.width > 1 ? container : frame
            let placement = RadialFan.placement(origin: origin, in: bounds)

            ZStack {
                ForEach(NotePressAction.allCases, id: \.self) { action in
                    let center = placement.centers[action] ?? origin
                    actionCircle(action, isHovered: hovered == action)
                        .position(x: center.x - frame.minX, y: center.y - frame.minY)
                }

                if let hovered {
                    Text(hovered.title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(.primary)
                        .position(
                            x: placement.label.x - frame.minX,
                            y: placement.label.y - frame.minY
                        )
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hovered)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
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

