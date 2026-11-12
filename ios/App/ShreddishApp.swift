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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .modelContainer(container)
    }
}
