import Foundation

// `TravelMode --status | --desk | --travel` works from Terminal or scripts, with no window.
if let argument = CommandLine.arguments.dropFirst().first, argument.hasPrefix("-") {
    exit(CLI.run(argument))
}

TravelModeApp.main()
