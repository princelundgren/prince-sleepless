import Foundation
import PrinceSleeplessCore

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: print-requirement <team-identifier>\n".utf8))
    exit(EX_USAGE)
}
print(ListenerRequirement.string(team: arguments[1], developerID: true))
