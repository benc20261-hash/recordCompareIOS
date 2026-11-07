import SwiftUI

@main
struct RecordCompareIOSApp: App {
    @StateObject private var store = ProductStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
                .onAppear {
                    store.loadIfNeeded()
                }
        }
    }
}
