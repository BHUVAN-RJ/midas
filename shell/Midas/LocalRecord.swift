import Foundation

// Its own file so the widget extension can compile it without the store (the Sidekick widget's
// tap preview, shell/Midas/SidekickWidgetTapPreview.swift).

/// One record as a Sidekick wrote it, with the Sidekick that owns it.
struct LocalRecord: Equatable, Sendable {
    let sidekickId: String
    let key: String
    let value: JSONValue
}
