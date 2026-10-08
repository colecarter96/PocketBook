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
    private let restThumbHeight: CGFloat = 18
    private let activeThumbHeight: CGFloat = 36

    var body: some View {
        GeometryReader { geometry in
            let clampedProgress = min(1, max(0, progress))
            let travel = max(geometry.size.height - activeThumbHeight, 1)
            let thumbY = clampedProgress * travel
            let thumbHeight = isDragging ? activeThumbHeight : restThumbHeight
            let thumbOffset = thumbY + (activeThumbHeight - thumbHeight) / 2

            ZStack(alignment: .topTrailing) {
                rail(thumbOffset: thumbOffset, thumbHeight: thumbHeight)
                    .animation(.easeInOut(duration: 0.22), value: isDragging)

                if isDragging, let date {
                    dateIndicator(date)
                        .offset(y: thumbY - 2)
                        .padding(.trailing, hitWidth)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isDragging)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(railHitShape(height: geometry.size.height))
            .gesture(dragGesture(height: geometry.size.height))
        }
        .frame(width: hitWidth)
        .accessibilityHidden(true)
    }

    private func rail(thumbOffset: CGFloat, thumbHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            Capsule()
                .fill(Color.primary.opacity(isDragging ? 0.55 : 0.28))
                .frame(width: isDragging ? 4 : 2, height: thumbHeight)
                .offset(y: thumbOffset)
        }
        .frame(width: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
    }

    private func dateIndicator(_ date: Date) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(date, format: .dateTime.month(.abbreviated).day())
                .textCase(.uppercase)
            Text(date, format: .dateTime.year())
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }

    private func railHitShape(height: CGFloat) -> Path {
        Path(CGRect(x: 0, y: 0, width: hitWidth, height: height))
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let travel = max(height - activeThumbHeight, 1)
                let y = value.location.y - (activeThumbHeight / 2)
                onDragChanged(min(1, max(0, y / travel)))
            }
            .onEnded { _ in
                onDragEnded()
            }
    }
}
