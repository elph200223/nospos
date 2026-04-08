//
//  NostalPosApp.swift
//  NostalPos
//

import SwiftUI
import UserNotifications

@main
struct NostalPosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .sound, .badge]
                    ) { _, _ in }
                }
        }
    }
}
