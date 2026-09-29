import SwiftUI

@main
struct MikrofonApp: App {
    @StateObject private var audio = LiveAudioEngine()
    @StateObject private var library = SoundLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audio)
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
