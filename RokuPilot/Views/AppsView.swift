import SwiftUI

struct AppsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 14)]

    private var filtered: [RokuApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.apps : model.apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let err = model.appsError, model.apps.isEmpty {
                    ContentUnavailableView("Can't load apps", systemImage: "wifi.exclamationmark", description: Text(err))
                        .padding(.top, 80)
                } else if model.apps.isEmpty {
                    ProgressView().padding(.top, 120)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filtered) { app in
                            Button { model.launch(app) } label: {
                                VStack(spacing: 8) {
                                    AppIconView(appID: app.id, name: app.name, size: 96)
                                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                                    Text(app.name)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .foregroundStyle(.white)
                                }
                                .overlay(alignment: .topTrailing) {
                                    if app.id == model.status.appID {
                                        Circle().fill(Theme.green).frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                                            .offset(x: 4, y: -4)
                                    }
                                }
                            }
                            .buttonStyle(PressableStyle(scale: 0.92))
                        }
                    }
                    .padding()
                }
            }
            .screenBackground()
            .navigationTitle("Apps")
            .searchable(text: $query, prompt: "Find an app")
            .refreshable { await model.loadApps() }
            .task { if model.apps.isEmpty { await model.loadApps() } }
        }
    }
}
