import Foundation
import PrinceSleeplessCore

struct Store {
    private enum Key {
        static let state = "controllerState"
        static let preferences = "preferences"
        static let build = "build"
        static let bootSession = "bootSession"
        static let cleanQuit = "cleanQuit"
    }

    private let defaults = UserDefaults.standard

    var state: ControllerState {
        decoded(ControllerState.self, forKey: Key.state) ?? ControllerState()
    }

    /// The saved preferences, clamped to the ranges Settings offers; the defaults when none are
    /// saved or they won't decode.
    var preferences: Preferences {
        (decoded(Preferences.self, forKey: Key.preferences) ?? Preferences()).clamped()
    }

    func save(_ state: ControllerState, _ preferences: Preferences) {
        encode(state, forKey: Key.state)
        encode(preferences, forKey: Key.preferences)
    }

    var lastBuild: String? {
        get { defaults.string(forKey: Key.build) }
        nonmutating set { defaults.set(newValue, forKey: Key.build) }
    }

    var lastBootSession: UUID? {
        get { defaults.string(forKey: Key.bootSession).flatMap(UUID.init(uuidString:)) }
        nonmutating set { defaults.set(newValue?.uuidString, forKey: Key.bootSession) }
    }

    var cleanQuit: Bool {
        get { defaults.bool(forKey: Key.cleanQuit) }
        nonmutating set { defaults.set(newValue, forKey: Key.cleanQuit) }
    }

    private func decoded<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            appLog.error("Couldn't decode the saved \(key, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private func encode(_ value: some Encodable, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            appLog.error("Couldn't save the \(key, privacy: .public): \(error, privacy: .public)")
        }
    }
}
