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

    init(text: String, createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
        self.boards = []
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
