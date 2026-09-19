import ArgumentParser
import DashboardDomain
import DashboardPersistenceJSON
import DashboardServer
import DashboardService

struct SettingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Show or change server settings (settings.json, applied live).",
        subcommands: [Show.self, Set.self]
    )

    static func service(home: String) -> SettingsService {
        SettingsService(store: JSONSettingsStore(path: ServerConfig(home: home).settingsPath))
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the current settings.")

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            try await failing {
                try Output.json(try await SettingsCommand.service(home: global.resolvedHome).current())
            }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change settings; omitted options keep their value.")

        @OptionGroup var global: GlobalOptions

        @Option(name: .customLong("default-storage"), help: "Format for new projects: json or sqlite.")
        var defaultStorage: StorageKind?

        @Option(name: .customLong("cors-origin"), parsing: .upToNextOption, help: "Allowed browser origins (replaces the list).")
        var corsOrigins: [String] = []

        @Flag(name: .customLong("clear-cors"), help: "Remove every allowed origin.")
        var clearCors = false

        func run() async throws {
            try await failing {
                let origins: [String]? = clearCors ? [] : (corsOrigins.isEmpty ? nil : corsOrigins)
                let updated = try await SettingsCommand.service(home: global.resolvedHome)
                    .update(defaultStorage: defaultStorage, corsOrigins: origins)
                try Output.json(updated)
            }
        }
    }
}
