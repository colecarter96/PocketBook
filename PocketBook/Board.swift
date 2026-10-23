//
//  Board.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import Foundation
import SwiftData

@Model
final class Board {
    var name: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \Note.boards)
    var notes: [Note]? = []

    var listedNotes: [Note] { notes ?? [] }

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.notes = []
    }
}
