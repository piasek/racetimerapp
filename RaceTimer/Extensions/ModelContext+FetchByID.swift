import Foundation
import SwiftData

extension ModelContext {
    /// Fetch a single model by its UUID `id` property.
    /// Works around Swift 6 #Predicate KeyPath Sendable issues with SwiftData.
    func fetchByID<T: PersistentModel>(_ type: T.Type, id: UUID) throws -> T?
    where T: Identifiable, T.ID == UUID {
        let descriptor = FetchDescriptor<T>()
        return try fetch(descriptor).first { $0.id == id }
    }
}
