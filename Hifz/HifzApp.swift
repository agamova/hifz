import SwiftData
import SwiftUI

@main
struct HifzApp: App {
    @State private var store = QuranStore()

    var body: some Scene {
        WindowGroup {
            SurahListView()
                .environment(store)
        }
        .modelContainer(for: LearnedAyah.self)
    }
}
