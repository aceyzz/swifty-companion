//
//  _2SwiftCompanionApp.swift
//  42SwiftCompanion
//
//  Created by XVI on 16/08/2025.
//

import SwiftUI

@main
struct _2SwiftCompanionApp: App {
    @StateObject private var authService = AuthService.shared
    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .onAppear {
                authService.checkAuthentication()
            }
        }
    }
}
