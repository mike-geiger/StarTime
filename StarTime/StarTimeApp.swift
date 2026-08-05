//
//  StarTimeApp.swift
//  StarTime
//
//  Created by Michael Geiger on 7/9/26.
//

import SwiftUI
import FirebaseCore

@main
struct StarTimeApp: App {
    @StateObject private var auth = AuthService()

    init() {
        FirebaseApp.configure()
        // Chores/Rewards still run on Firestore until Phases 3-4, so Firebase
        // stays configured; only Auth has moved to Cognito so far.
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }
}
