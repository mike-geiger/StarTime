//
//  StarTimeApp.swift
//  StarTime
//
//  Created by Michael Geiger on 7/9/26.
//

import SwiftUI

@main
struct StarTimeApp: App {
    @StateObject private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }
}
