import SwiftUI

struct SidekickEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let symbolName: String
    let backgroundColor: Color
}

/// Hand-listed until manifests come from the backend (D5, D6). Every user gets every Sidekick.
enum SidekickCatalog {
    static let all: [SidekickEntry] = [
        SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundColor: .orange),
        SidekickEntry(id: "calendar", name: "Calendar", symbolName: "calendar", backgroundColor: .red),
        SidekickEntry(id: "birthdays", name: "Birthdays", symbolName: "gift", backgroundColor: .pink),
    ]
}
