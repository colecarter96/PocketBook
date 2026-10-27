//
//  TimeRail.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftUI

struct TimeRail: View {
    var progress: CGFloat
    var date: Date?
    var isDragging: Bool
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: () -> Void

    private let hitWidth: CGFloat = 44
    private let thumbHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let clampedProgress = min(1, max(0, progress))
            let travel = max(geometry.size.height - thumbHeight, 1)
            let thumbY = clampedProgress * travel

            let labelHeight: CGFloat = 36
            let screenPad = max(16, geometry.safeAreaInsets.leading)
            let topPad = max(16, geometry.safeAreaInsets.top)
            let bottomPad = max(16, geometry.safeAreaInsets.bottom)
            let minY = topPad
            let maxY = max(minY, geometry.size.height - bottomPad - labelHeight)
            let labelY = min(maxY, max(minY, thumbY + thumbHeight / 2 - labelHeight / 2))
            let trailingInset = hitWidth + 12 + max(0, geometry.safeAreaInsets.trailing)

            ZStack(alignment: .topTrailing) {
                rail(thumbOffset: thumbY, grabbed: isDragging)

                Group {
                    if isDragging, let date {
                        dateLabel(date)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.leading, screenPad)
                            .padding(.trailing, trailingInset)
                            .offset(y: labelY)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isDragging)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(railHitShape(in: geometry.size))
            .gesture(dragGesture(height: geometry.size.height))
        }
        .accessibilityHidden(true)
    }

    private func rail(thumbOffset: CGFloat, grabbed: Bool) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: 2, height: thumbHeight)
                .scaleEffect(grabbed ? 2.5 : 1, anchor: .center)
                .animation(.easeOut(duration: 0.12), value: grabbed)
                .offset(y: thumbOffset)
        }
        .frame(width: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
    }

    private func dateLabel(_ date: Date) -> some View {
        Text(date, format: .dateTime.month(.abbreviated).day())
            .textCase(.uppercase)
            .font(.title3.weight(.medium))
            .foregroundStyle(.primary)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .allowsHitTesting(false)
    }

    private func railHitShape(in size: CGSize) -> Path {
        Path(CGRect(x: max(0, size.width - hitWidth), y: 0, width: hitWidth, height: size.height))
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let travel = max(height - thumbHeight, 1)
                let y = value.location.y - (thumbHeight / 2)
                onDragChanged(min(1, max(0, y / travel)))
            }
            .onEnded { _ in
                onDragEnded()
            }
    }
}
