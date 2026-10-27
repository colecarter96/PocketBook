//
//  NoteImage.swift
//  PocketBook
//

import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct PickedNoteImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedNoteImage(data: data)
        }
        FileRepresentation(importedContentType: .image) { file in
            let data = try Data(contentsOf: file.file)
            return PickedNoteImage(data: data)
        }
    }
}

enum NoteImageStore {
    static var directory: URL {
        PocketCloudStore.localDirectoryURL(folder: "NoteImages")
    }

    static func fileURL(_ fileName: String) -> URL {
        PocketCloudStore.fileURL(fileName, folder: "NoteImages")
    }

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        PocketCloudStore.remove(fileName, folder: "NoteImages")
    }

    static func deleteAll(except kept: Set<String>) {
        for name in PocketCloudStore.fileNames(in: "NoteImages") where !kept.contains(name) {
            PocketCloudStore.remove(name, folder: "NoteImages")
        }
    }

    @MainActor
    static func importPhotos(_ items: [PhotosPickerItem], into note: Note) async {
        for item in items {
            guard let picked = try? await item.loadTransferable(type: PickedNoteImage.self) else { continue }
            let data = picked.data
            let fileName = await Task.detached(priority: .userInitiated) {
                writeJPEG(from: data)
            }.value
            if let fileName {
                remember(fileName, on: note)
            }
        }
        try? note.modelContext?.save()
    }

    @MainActor
    static func append(_ image: UIImage, to note: Note) async {
        let fileName = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                writeJPEG(from: image)
            }
        }.value
        guard let fileName else { return }
        remember(fileName, on: note)
        try? note.modelContext?.save()
    }

    @MainActor
    private static func remember(_ fileName: String, on note: Note) {
        var names = note.imageFileNames
        names.append(fileName)
        note.imageFileNames = names
    }

    static func thumbnail(fileName: String, maxPixel: CGFloat = 240) -> UIImage? {
        image(fileName: fileName, maxPixel: maxPixel)
    }

    static func fullImage(fileName: String) -> UIImage? {
        image(fileName: fileName, maxPixel: 2000)
    }

    private static func image(fileName: String, maxPixel: CGFloat) -> UIImage? {
        let source = CGImageSourceCreateWithURL(fileURL(fileName) as CFURL, nil)
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func writeJPEG(from data: Data) -> String? {
        autoreleasepool {
            guard let jpeg = compressedJPEG(from: data) else { return nil }
            return store(jpeg)
        }
    }

    private static func writeJPEG(from image: UIImage) -> String? {
        guard let jpeg = compressedJPEG(image) else { return nil }
        return store(jpeg)
    }

    private static func store(_ jpeg: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        let url = PocketCloudStore.localFileURL(name, folder: "NoteImages")
        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        PocketCloudStore.publish(name, folder: "NoteImages")
        return name
    }

    private static func compressedJPEG(from data: Data) -> Data? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumb: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func compressedJPEG(_ image: UIImage) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        let factor = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: pixelWidth * factor, height: pixelHeight * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

struct NoteHitFrames: Equatable {
    var editor: CGRect = .zero
    var memo: CGRect = .zero
    var transcriptToggle: CGRect = .zero
    var transcriptField: CGRect = .zero
    var images: [String: CGRect] = [:]
    var lists: [String: CGRect] = [:]
    var check: CGRect = .zero
}

struct NoteHitPreference: PreferenceKey {
    static var defaultValue = NoteHitFrames()

    static func reduce(value: inout NoteHitFrames, nextValue: () -> NoteHitFrames) {
        let next = nextValue()
        if next.editor != .zero {
            value.editor = next.editor
        }
        if next.memo != .zero {
            value.memo = next.memo
        }
        if next.transcriptToggle != .zero {
            value.transcriptToggle = next.transcriptToggle
        }
        if next.transcriptField != .zero {
            value.transcriptField = next.transcriptField
        }
        if next.check != .zero {
            value.check = next.check
        }
        value.images.merge(next.images, uniquingKeysWith: { $1 })
        value.lists.merge(next.lists, uniquingKeysWith: { $1 })
    }
}

struct NoteImageStrip: View {
    var fileNames: [String]
    var isArranging = false
    var onOpen: (String) -> Void
    var onDelete: ((String) -> Void)? = nil
    var onFinishArrange: (() -> Void)? = nil

    var body: some View {
        if !fileNames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(fileNames, id: \.self) { fileName in
                        NoteImageThumbnail(
                            fileName: fileName,
                            showsDelete: isArranging,
                            onDelete: onDelete.map { delete in { delete(fileName) } }
                        ) {
                            onOpen(fileName)
                        }
                    }
                    if isArranging {
                        keepPhotosMark
                    }
                }
            }
        }
    }

    private var keepPhotosMark: some View {
        let mark = Image(systemName: "checkmark")
            .pocketBody(weight: .bold)
            .foregroundStyle(.black)
            .frame(width: 36, height: 36)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: NoteHitPreference.self,
                        value: NoteHitFrames(check: geometry.frame(in: .global))
                    )
                }
            }
            .accessibilityLabel("Keep Photos")

        return Group {
            if let onFinishArrange {
                Button(action: onFinishArrange) { mark }
                    .buttonStyle(.plain)
            } else {
                mark
            }
        }
    }
}

private struct NoteImageThumbnail: View {
    var fileName: String
    var showsDelete: Bool
    var onDelete: (() -> Void)? = nil
    var onTap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: onTap) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.primary.opacity(0.06)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if showsDelete && onDelete == nil {
                    deleteBadge
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo")
        .overlay(alignment: .topTrailing) {
            if showsDelete, let onDelete {
                Button(action: onDelete) {
                    deleteBadge
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Photo")
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: NoteHitPreference.self,
                    value: NoteHitFrames(images: [fileName: geometry.frame(in: .global)])
                )
            }
        }
        .task {
            let name = fileName
            image = await Task.detached(priority: .userInitiated) {
                NoteImageStore.thumbnail(fileName: name)
            }.value
        }
    }

    private var deleteBadge: some View {
        Image(systemName: "xmark")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.black)
            .frame(width: 22, height: 22)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.16), radius: 4, y: 1)
            .padding(4)
    }
}

struct NoteImagePreview: View {
    var fileName: String
    var onClose: () -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .task {
            let name = fileName
            image = await Task.detached(priority: .userInitiated) {
                NoteImageStore.fullImage(fileName: name)
            }.value
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.onImage = onImage
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (UIImage?) -> Void

        init(onImage: @escaping (UIImage?) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}
