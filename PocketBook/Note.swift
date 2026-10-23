//
//  Note.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import Foundation
import SwiftData

@Model
final class Note {
    var text: String = ""
    var createdAt: Date = Date()
    var boards: [Board]? = []
    var audioFileName: String? = nil
    var audioDuration: Double = 0
    var transcript: String = ""
    var imageFileNames: [String] = []
    var revisitDone: Bool = false
    var revisitAfter: Date? = nil
    var widgetKey: String = ""

    init(text: String, createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
        self.boards = []
        self.audioFileName = nil
        self.audioDuration = 0
        self.transcript = ""
        self.imageFileNames = []
        self.revisitDone = false
        self.revisitAfter = nil
        self.widgetKey = UUID().uuidString
    }

    var lists: [Board] {
        get { boards ?? [] }
        set { boards = newValue }
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && audioFileName == nil
            && imageFileNames.isEmpty
    }

    func isOn(_ board: Board) -> Bool {
        lists.contains { $0.persistentModelID == board.persistentModelID }
    }

    func toggleBoard(_ board: Board) {
        var next = lists
        if let index = next.firstIndex(where: { $0.persistentModelID == board.persistentModelID }) {
            next.remove(at: index)
        } else {
            next.append(board)
        }
        boards = next
    }
}
