import Foundation

/// Builds the store's write gate: every write, from a page or from the shell itself, gets its
/// `$type` stamped and is checked against its record type before it is stored (unified data
/// plan, section 5). The shell's own types (`widget:`, `request:`) apply in every Sidekick; a
/// Sidekick's own types come from its manifest, as the directory last fetched it. A Sidekick
/// whose manifest declares no types is not content-checked, as before schemas.
@MainActor
enum RecordTypeGate {
    static func make(engine: RecordSchemaEngine, directory: SidekickDirectory) -> RecordWriteGate {
        let typesProvider: @MainActor (String) -> JSONValue? = directory.types(forSidekickId:)
        return make(engine: engine, typesProvider: typesProvider)
    }

    /// `typesProvider` gives a Sidekick's manifest `types`, or nil when it has none.
    static func make(engine: RecordSchemaEngine, typesProvider: @escaping @MainActor (String) -> JSONValue?) -> RecordWriteGate {
        let gate: RecordWriteGate = { sidekickId, key, value in
            let types = typesFor(key: key, sidekickId: sidekickId, engine: engine, typesProvider: typesProvider)
            guard let types else {
                return value
            }
            let stampedValue = engine.stampType(types: types, key: key, value: value)
            if let problem = engine.checkRecord(types: types, key: key, value: stampedValue) {
                throw RecordRefusal(reason: problem)
            }
            return stampedValue
        }
        return gate
    }

    // The shell's types win for their prefixes; otherwise the Sidekick's own.
    private static func typesFor(key: String, sidekickId: String, engine: RecordSchemaEngine, typesProvider: @MainActor (String) -> JSONValue?) -> JSONValue? {
        if engine.typeName(types: engine.shellTypes, key: key) != nil {
            return engine.shellTypes
        }
        return typesProvider(sidekickId)
    }
}
