//
//  NFLApp.swift
//  NFL
//
//  Created by T G Schnetzer on 5/13/26.
//

import SwiftUI

@main
struct NFLApp: App {
    @State private var weekSelection = WeekSelection()
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(weekSelection)
                .environment(settings)
        }
    }
}
