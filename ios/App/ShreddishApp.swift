import ShreddishCore
import SwiftData
import SwiftUI

@main
struct ShreddishApp: App {
    @State private var model: AppModel
    private let container: ModelContainer

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
        container = ModelContainerFactory.make(inMemory: model.isUITest)
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.green)
                .font(Theme.text())
                .foregroundStyle(Theme.ink)
        }
        .modelContainer(container)
    }
}
