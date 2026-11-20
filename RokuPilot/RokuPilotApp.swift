import SwiftUI

@main
struct RokuPilotApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
                .onChange(of: scenePhase) {
                    if scenePhase == .active { model.startPolling() } else { model.stopPolling() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            AssistantView()
                .tabItem { Label("Pilot", systemImage: "sparkles") }
            RemoteView()
                .tabItem { Label("Remote", systemImage: "av.remote.fill") }
            AppsView()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2.fill") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .fullScreenCover(isPresented: $model.showSetup) {
            NavigationStack {
                SettingsView(isOnboarding: true) {
                    model.showSetup = false
                    model.startPolling()
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.cyan)
            .environment(model)
        }
    }
}
