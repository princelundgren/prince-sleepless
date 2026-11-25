import Foundation
import PrinceSleeplessCore
import Security

// A dispatch source installs no handler, so without this SIGTERM's default action kills the
// process before the source's handler runs.
signal(SIGTERM, SIG_IGN)

/// The team identifier from this process's own valid code signature, or `nil` when unsigned,
/// invalid or signed without a team.
func signingTeam() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
          SecCodeCheckValidity(code, [], nil) == errSecSuccess
    else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let information = information as? [String: Any]
    else { return nil }
    return information[kSecCodeInfoTeamIdentifier as String] as? String
}

/// `kern.bootsessionuuid`, or `nil` when it can't be read.
func currentBootSession() -> UUID? {
    var size = 0
    guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
    return UUID(uuidString: String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self))
}

let service = HelperService()

let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM)
terminationSource.setEventHandler { service.terminate() }
terminationSource.activate()

guard let bootSession = currentBootSession() else {
    helperLog.fault("Couldn't read kern.bootsessionuuid; not accepting connections")
    exit(EXIT_FAILURE)
}
service.runBootCheck(bootFile: .standard, current: bootSession)

guard let team = signingTeam() else {
    helperLog.fault("No team in the helper's signature; not accepting connections")
    exit(EXIT_FAILURE)
}

#if DEBUG
let requiresDeveloperID = false
#else
let requiresDeveloperID = true
#endif
let listener = NSXPCListener(machServiceName: sleeplessHelperMachService)
listener.setConnectionCodeSigningRequirement(ListenerRequirement.string(team: team, developerID: requiresDeveloperID))
let listenerDelegate = HelperListenerDelegate(service: service)
listener.delegate = listenerDelegate
listener.resume()

dispatchMain()
