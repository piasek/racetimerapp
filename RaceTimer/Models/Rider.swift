import Foundation
import SwiftData

@Model
final class Rider {
    @Attribute(.unique) var id: UUID
    var firstName: String
    var lastName: String?
    var bibNumber: Int?
    var category: String?
    var notes: String?

    var session: Session?

    @Relationship(deleteRule: .cascade, inverse: \Run.rider)
    var runs: [Run]

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String? = nil,
        bibNumber: Int? = nil,
        category: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.bibNumber = bibNumber
        self.category = category
        self.notes = notes
        self.runs = []
    }

    var displayName: String {
        if let lastName {
            return "\(firstName) \(lastName)"
        }
        if let bibNumber {
            return "\(firstName) #\(bibNumber)"
        }
        return firstName
    }
}
