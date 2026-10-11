//
//  RadialPress.swift
//  PocketBook
//

import SwiftUI
import UIKit

enum NotePressAction: Hashable {
    case copy
    case memo
    case board
    case photos
    case delete

    var title: String {
        switch self {
        case .copy: "Copy"
        case .memo: "Memo"
        case .board: "Board"
        case .photos: "Photos"
        case .delete: "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: "doc.on.doc"
        case .memo: "mic.slash"
        case .board: "square.stack"
        case .photos: "photo"
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
    private static let circleMargin: CGFloat = 40

    static func placement(
        origin: CGPoint,
        actions: [NotePressAction],
        in container: CGRect
    ) -> RadialPlacement {
        let safe = safeRect(in: container, margin: circleMargin)
        var radius = restingRadius
        var aim = aimAngle(origin: origin, safe: safe, radius: radius, count: actions.count)
        while overflow(origin: origin, aim: aim, radius: radius, count: actions.count, safe: safe) > 1, radius > 64 {
            radius -= 4
            aim = aimAngle(origin: origin, safe: safe, radius: radius, count: actions.count)
        }

        var centers: [NotePressAction: CGPoint] = [:]
        for (index, action) in actions.enumerated() {
            let angle = aim + offset(index: index, count: actions.count)
            centers[action] = point(origin: origin, angle: angle, radius: radius)
        }
        return RadialPlacement(centers: centers, label: labelPoint(origin: origin, in: container))
    }

    private static let step: CGFloat = 0.76

    private static func offset(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        return (CGFloat(index) - CGFloat(count - 1) / 2) * step
    }

    private static func aimAngle(origin: CGPoint, safe: CGRect, radius: CGFloat, count: Int) -> CGFloat {
        let preferred: CGFloat = (origin.y - safe.minY) >= (safe.maxY - origin.y) ? -.pi / 2 : .pi / 2
        if overflow(origin: origin, aim: preferred, radius: radius, count: count, safe: safe) <= 1 {
            return preferred
        }

        let turnStep: CGFloat = .pi / 60
        for index in 1...60 {
            let turn = CGFloat(index) * turnStep
            let clockwise = preferred + turn
            let counter = preferred - turn
            let clockwiseOverflow = overflow(origin: origin, aim: clockwise, radius: radius, count: count, safe: safe)
            let counterOverflow = overflow(origin: origin, aim: counter, radius: radius, count: count, safe: safe)
            if clockwiseOverflow <= 1 { return clockwise }
            if counterOverflow <= 1 { return counter }
        }
        return preferred
    }

    private static func overflow(
        origin: CGPoint,
        aim: CGFloat,
        radius: CGFloat,
        count: Int,
        safe: CGRect
    ) -> CGFloat {
        (0..<max(count, 1)).reduce(0) { total, index in
            let center = point(origin: origin, angle: aim + offset(index: index, count: count), radius: radius)
            let dx = max(safe.minX - center.x, center.x - safe.maxX, 0)
            let dy = max(safe.minY - center.y, center.y - safe.maxY, 0)
            return total + dx + dy
        }
    }

    private static func labelPoint(origin: CGPoint, in container: CGRect) -> CGPoint {
        let towardLeft = origin.x > container.midX
        let x = origin.x + (towardLeft ? -72 : 72)
        let y = origin.y - 112
        return CGPoint(
            x: min(max(x, container.minX + 64), container.maxX - 64),
            y: min(max(y, container.minY + 28), container.maxY - 28)
        )
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
    var actions: [NotePressAction]
    var hovered: NotePressAction?
    var container: CGRect

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let bounds = container.width > 1 ? container : frame
            let placement = RadialFan.placement(origin: origin, actions: actions, in: bounds)

            ZStack {
                ForEach(actions, id: \.self) { action in
                    let center = placement.centers[action] ?? origin
                    actionCircle(action, isHovered: hovered == action)
                        .position(x: center.x - frame.minX, y: center.y - frame.minY)
                }

                if let hovered {
                    Text(hovered.title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 140, alignment: .center)
                        .position(
                            x: placement.label.x - frame.minX,
                            y: placement.label.y - frame.minY
                        )
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
            .foregroundStyle(Color.black)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(action == .delete ? Color.red : Color.white)
                    .shadow(color: .black.opacity(0.18), radius: isHovered ? 16 : 10, y: 4)
            }
    }
}

