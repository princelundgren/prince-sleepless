/// The code-signing requirement the helper's listener sets, so only the app signed by the
/// helper's own team may connect.
public enum ListenerRequirement {
    /// The app's identifier, `anchor apple generic` and `team` as the leaf's OU; with
    /// `developerID`, also the Developer ID intermediate and leaf certificate fields. `team` is
    /// inserted as given, so it must be a team identifier, never untrusted input.
    public static func string(team: String, developerID: Bool) -> String {
        let developerIDFields = developerID
            ? " and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            : ""
        return #"identifier "com.princelundgren.princesleepless" and anchor apple generic"#
            + developerIDFields
            + #" and certificate leaf[subject.OU] = "\#(team)""#
    }
}
