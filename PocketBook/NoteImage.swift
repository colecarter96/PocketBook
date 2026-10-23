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
        PocketCloudStore.directory(folder: "NoteImages")
    }

    static func fileURL(_ fileName: String) -> URL {
        PocketCloudStore.fileURL(fileName, folder: "NoteImages")
    }

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: fileURL(fileName))
    }

    static func deleteAll(except kept: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in files where !kept.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    static func importPhotos(_ items: [PhotosPickerItem], into note: Note) async {
        for item in items {
            guard let picked = try? await item.loadTransferable(type: PickedNoteImage.self) else { continue }
            append(picked.data, to: note)
        }
        try? note.modelContext?.save()
    }

    @MainActor
    static func append(_ data: Data, to note: Note) {
        guard let image = UIImage(data: data) else { return }
        append(image, to: note)
    }

    @MainActor
    static func append(_ image: UIImage, to note: Note) {
        guard let jpeg = compressedJPEG(image) else { return }
        let url = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            return
        }
        var names = note.imageFileNames
        names.append(url.lastPathComponent)
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

    private static func compressedJPEG(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
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
            image = NoteImageStore.thumbnail(fileName: fileName)
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
            image = NoteImageStore.fullImage(fileName: fileName)
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
