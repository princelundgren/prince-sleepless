/// The helper's connections that guard the sleep-disabled flag, by connection id.
public struct GuardBook: Sendable {
    private var guarding: Set<Int> = []

    public init() {}

    /// `true` while no connection guards the flag.
    public var isEmpty: Bool { guarding.isEmpty }

    /// Guards connection `id`; guarding it again changes nothing.
    public mutating func guardConnection(_ id: Int) {
        guarding.insert(id)
    }

    /// Stops guarding connection `id`. Returns `true` when it was the last guard, so the flag
    /// is now nobody's to keep; `false` when others still guard or `id` didn't.
    public mutating func release(_ id: Int) -> Bool {
        guarding.remove(id) != nil && guarding.isEmpty
    }
}
