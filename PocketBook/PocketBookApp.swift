//
//  PocketBookApp.swift
//  PocketBook
//
//  Created by Cole Carter on 10/7/26.
//

import SwiftData
import SwiftUI

@main
struct PocketBookApp: App {
    var body: some Scene {
        WindowGroup {
            TimelineView()
        }
        .modelContainer(for: Note.self)
    }
}
