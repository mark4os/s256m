//
//  s256mApp.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import SwiftUI

@main
struct s256mApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 760, height: 800)
        .windowResizability(.contentMinSize)
    }
}
