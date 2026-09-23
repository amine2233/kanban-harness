import ArgumentParser
import DashboardDomain
import DashboardRuntime

struct SettingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Show or change server settings (settings.json, applied live).",
        subcommands: [Show.self, Set.self]
    )

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the current settings.")

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            try await failing {
                try await Output.json(Runtime.run(global) {
                    try await $0.make(SettingsCommandsKey.self).current()
                })
            }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration =
            CommandConfiguration(abstract: "Change settings; omitted options keep their value.")

        @OptionGroup var global: GlobalOptions

        @Option(name: .customLong("default-storage"), help: "Format for new projects: json or sqlite.")
        var defaultStorage: StorageKind?

        @Option(
            name: .customLong("cors-origin"),
            parsing: .upToNextOption,
            help: "Allowed browser origins (replaces the list)."
        )
        var corsOrigins: [String] = []

        @Flag(name: .customLong("clear-cors"), help: "Remove every allowed origin.")
        var clearCors = false

        func run() async throws {
            try await failing {
                let origins: [String]? = clearCors ? [] : (corsOrigins.isEmpty ? nil : corsOrigins)
                let defaultStorage = defaultStorage
                try await Output.json(Runtime.run(global) {
                    try await $0.make(SettingsCommandsKey.self).update(
                        defaultStorage: defaultStorage,
                        corsOrigins: origins
                    )
                })
            }
        }
    }
}
