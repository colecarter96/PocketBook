//
//  PocketReading.swift
//  PocketBook
//

import SwiftUI
import UIKit

enum PocketFontChoice: String, CaseIterable, Identifiable {
    case helvetica
    case serif
    case rounded
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .helvetica: "Helvetica"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .mono: "Mono"
        }
    }

    /// Helvetica Neue and monospace draw larger than Serif and Rounded at the same point size.
    private var sizeScale: CGFloat {
        switch self {
        case .helvetica, .mono: 0.86
        case .serif, .rounded: 1
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * sizeScale
        return switch self {
        case .helvetica:
            .custom(Self.helveticaName(weight), size: scaled)
        case .serif:
            .system(size: scaled, weight: weight, design: .serif)
        case .rounded:
            .system(size: scaled, weight: weight, design: .rounded)
        case .mono:
            .system(size: scaled, weight: weight, design: .monospaced)
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        let scaled = size * sizeScale
        if self == .helvetica {
            return UIFont(name: Self.helveticaName(.regular), size: scaled) ?? .systemFont(ofSize: scaled, weight: .medium)
        }
        let base = UIFont.systemFont(ofSize: scaled)
        let design: UIFontDescriptor.SystemDesign = switch self {
        case .helvetica: .default
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: scaled)
    }

    static func stored(_ raw: String) -> PocketFontChoice {
        if raw == "system" { return .helvetica }
        return PocketFontChoice(rawValue: raw) ?? .helvetica
    }

    private static func helveticaName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black:
            "HelveticaNeue-Bold"
        case .semibold, .medium:
            "HelveticaNeue-Bold"
        default:
            "HelveticaNeue-Medium"
        }
    }
}

enum PocketTextSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var pointSize: CGFloat {
        switch self {
        case .small: 16
        case .medium: 18
        case .large: 21
        case .extraLarge: 25
        }
    }

    var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .extraLarge: "XL"
        }
    }
}

enum PocketColorway: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var scheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var canvas: Color {
        Color(.systemBackground)
    }

    static func current(colorwayRaw: String, appearanceRaw: String) -> PocketColorway {
        if appearanceRaw == "dark" || colorwayRaw == "dark" { return .dark }
        return .light
    }
}

struct PocketReading: Equatable {
    var font: PocketFontChoice
    var size: PocketTextSize
    var colorway: PocketColorway

    func bodyFont(weight: Font.Weight = .regular) -> Font {
        font.font(size: size.pointSize, weight: weight)
    }
    var bodyUIFont: UIFont { font.uiFont(size: size.pointSize) }

    static let standard = PocketReading(font: .helvetica, size: .medium, colorway: .light)
}

private struct PocketReadingKey: EnvironmentKey {
    static let defaultValue = PocketReading.standard
}

extension EnvironmentValues {
    var pocketReading: PocketReading {
        get { self[PocketReadingKey.self] }
        set { self[PocketReadingKey.self] = newValue }
    }
}

struct PocketCanvas: View {
    @Environment(\.pocketReading) private var reading

    var body: some View {
        reading.colorway.canvas
    }
}

private struct PocketBodyFont: ViewModifier {
    @Environment(\.pocketReading) private var reading
    var weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(reading.bodyFont(weight: weight))
    }
}

extension View {
    func pocketBody(weight: Font.Weight = .regular) -> some View {
        modifier(PocketBodyFont(weight: weight))
    }
}

struct ReadingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pocketbook.font") private var fontRaw = PocketFontChoice.helvetica.rawValue
    @AppStorage("pocketbook.textSize") private var textSizeRaw = PocketTextSize.medium.rawValue

    private var font: PocketFontChoice {
        PocketFontChoice.stored(fontRaw)
    }

    private var textSize: PocketTextSize {
        PocketTextSize(rawValue: textSizeRaw) ?? .medium
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                    Text("A stream of your mind.")
                    .font(font.font(size: textSize.pointSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Font")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(PocketFontChoice.allCases) { choice in
                            Button {
                                fontRaw = choice.rawValue
                            } label: {
                                Text(choice.title)
                                    .font(choice.font(size: 17, weight: .regular))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        font == choice ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Size")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(PocketTextSize.allCases) { size in
                            Button {
                                textSizeRaw = size.rawValue
                            } label: {
                                Text(size.title)
                                    .font(font.font(size: size.pointSize * 0.72, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        textSize == size ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(PocketCanvas())
            .navigationTitle("Aa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
