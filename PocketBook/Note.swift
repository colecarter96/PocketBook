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

    init(text: String, createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
    }
}
