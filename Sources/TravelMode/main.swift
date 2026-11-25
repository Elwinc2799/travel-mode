import Foundation

// `TravelMode --status | --info | --desk | --travel | --help` works from Terminal or scripts, with
// no window. Any other arguments (macOS and debuggers sometimes add their own) start the app.
if let argument = CommandLine.arguments.dropFirst().first, CLI.options.contains(argument) {
    exit(CLI.run(argument))
}

TravelModeApp.main()
