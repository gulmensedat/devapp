import SwiftUI

/// Pencere: solda ince şerit, sağda seçili ekran (pano / tüm terminaller / proje).
struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = store

        HStack(spacing: 0) {
            RailView()

            Group {
                switch store.screen {
                case .dashboard:
                    DashboardView()
                case .terminals:
                    AllTerminalsScreen()
                case .project(let id):
                    if let project = store.project(id) {
                        ProjectScreen(project: project)
                    } else {
                        DashboardView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.18), value: store.screen)
        .background(Theme.bg)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .sheet(item: $store.newSessionRequest) { request in
            NewSessionSheet(request: request)
                .environment(store)
        }
        .sheet(item: $store.commandsEditRequest) { request in
            ProjectCommandsSheet(projectID: request.projectID)
                .environment(store)
        }
        .onOpenURL { url in
            // Widget'tan gelen bağlantılar: devapp://project/<id> vb.
            store.handleURL(url)
        }
        .onAppear {
            // Dock menüsünden pencere kapalıyken açabilmek için
            let open = openWindow
            store.openMainWindowAction = { open(id: "main") }
        }
        .alert(L("Bir sorun oluştu", "Something went wrong"), isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button(L("Tamam", "OK"), role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
