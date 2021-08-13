//
//  EmojiArtApp.swift
//  Shared
//
//  Created by Rocca on 8/13/21.
//

import SwiftUI

@main
struct EmojiArtApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: EmojiArtDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
