/// The `pmset` invocation that sets the sleep-disabled flag, as an executable and an argument
/// list, never a shell string.
public enum PmsetCommand {
    public static let executable = "/usr/bin/pmset"

    /// `-a disablesleep 1` to keep the Mac awake, `-a disablesleep 0` to let it sleep.
    public static func arguments(disableSleep: Bool) -> [String] {
        ["-a", "disablesleep", disableSleep ? "1" : "0"]
    }
}
