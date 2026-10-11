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
    var text: String
    var createdAt: Date
    var boards: [Board]
    var audioFileName: String? = nil
    var audioDuration: Double = 0
    var imageFileNames: [String] = []
    var revisitDone: Bool = false
    var revisitAfter: Date? = nil

    init(text: String, createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
        self.boards = []
        self.audioFileName = nil
        self.audioDuration = 0
        self.imageFileNames = []
        self.revisitDone = false
        self.revisitAfter = nil
    }

    func isOn(_ board: Board) -> Bool {
        boards.contains { $0.persistentModelID == board.persistentModelID }
    }

    func toggleBoard(_ board: Board) {
        if let index = boards.firstIndex(where: { $0.persistentModelID == board.persistentModelID }) {
            boards.remove(at: index)
        } else {
            boards.append(board)
        }
    }
}
