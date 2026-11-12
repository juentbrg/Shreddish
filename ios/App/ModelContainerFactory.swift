import Foundation
import ShreddishCore
import SwiftData

enum ModelContainerFactory {
    /// Store local sans CloudKit ; en mémoire pour previews et UI tests.
    static func make(inMemory: Bool) -> ModelContainer {
        do {
            return try ShreddishStore.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Store SwiftData impossible à ouvrir : \(error)")
        }
    }
}
