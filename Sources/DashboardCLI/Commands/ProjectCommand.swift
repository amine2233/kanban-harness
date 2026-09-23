import ArgumentParser
import DashboardDomain
import DashboardRuntime
import Foundation

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Register, list and inspect projects.",
        subcommands: [Add.self, List.self, Show.self, Remove.self, Boards.self, Storage.self]
    )

    struct Add: AsyncParsableCommand {
        static let configuration =
            CommandConfiguration(abstract: "Register a folder as a project (created and seeded if missing).")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Folder holding the project's kanban workspace.")
        var path: String

        @Option(help: "Display name; defaults to the folder name.")
        var name: String?

        @Option(
            help: "Workspace format written into the folder (json or sqlite); defaults to the settings' default_storage."
        )
        var storage: StorageKind?

        func run() async throws {
            try await failing {
                let absolute = Self.absolute(path)
                let requested = storage
                let project = try await Runtime.run(global) { services in
                    try await services.make(ProjectCommandsKey.self)
                        .add(name: name ?? Self.folderName(absolute), path: absolute, storage: requested)
                }
                try Output.json(project)
            }
        }

        static func absolute(_ path: String) -> String {
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(
                fileURLWithPath: expanded,
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
            return url.standardizedFileURL.path
        }

        static func folderName(_ path: String) -> String {
            let name = (path as NSString).lastPathComponent
            return name.isEmpty || name == "/" ? "project" : name
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List registered projects.")

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            try await failing {
                try await Output.json(Runtime.run(global) {
                    try await $0.make(ProjectCommandsKey.self).list()
                })
            }
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show one project by name or id.")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Project name or id.")
        var project: String

        func run() async throws {
            try await failing {
                try await Output.json(Runtime.run(global) {
                    try await $0.make(ProjectCommandsKey.self).get(.parse(project))
                })
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration =
            CommandConfiguration(abstract: "Unregister a project (files on disk are kept).")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Project name or id.")
        var project: String

        func run() async throws {
            try await failing {
                try await Output.json(Runtime.run(global) {
                    try await $0.make(ProjectCommandsKey.self).remove(.parse(project))
                })
            }
        }
    }

    struct Storage: AsyncParsableCommand {
        static let configuration =
            CommandConfiguration(
                abstract: "Convert a project's workspace to json or sqlite (the old file is kept)."
            )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Project name or id.")
        var project: String

        @Argument(help: "Target format: json or sqlite.")
        var storage: StorageKind

        func run() async throws {
            try await failing {
                try await Output.json(Runtime.run(global) {
                    try await $0.make(ProjectCommandsKey.self).changeStorage(.parse(project), to: storage)
                })
            }
        }
    }

    struct Boards: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the kanban boards inside a project.")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Project name or id.")
        var project: String

        func run() async throws {
            try await failing {
                try await Output.json(Runtime.run(global) {
                    try await $0.make(ProjectCommandsKey.self).boards(.parse(project))
                })
            }
        }
    }
}

extension StorageKind: ExpressibleByArgument {}
