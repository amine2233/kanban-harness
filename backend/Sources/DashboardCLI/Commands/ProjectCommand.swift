import ArgumentParser
import DashboardAPI
import DashboardDomain
import Foundation

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Register, list and inspect projects.",
        subcommands: [Add.self, List.self, Show.self, Remove.self, Boards.self]
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Register a folder as a project (created and seeded if missing).")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Folder holding the project's kanban workspace.")
        var path: String

        @Option(help: "Display name; defaults to the folder name.")
        var name: String?

        @Option(help: "Workspace format written into the folder (json).")
        var storage: StorageKind = .json

        func run() async throws {
            try await failing {
                let absolute = Self.absolute(path)
                let context = try await CLIContext.open(home: global.resolvedHome)
                let project = try await context.run {
                    try await $0.add(name: name ?? Self.folderName(absolute), path: absolute, storage: storage)
                }
                try Output.json(project)
            }
        }

        static func absolute(_ path: String) -> String {
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
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
                let context = try await CLIContext.open(home: global.resolvedHome)
                try Output.json(try await context.run { try await $0.list() })
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
                let context = try await CLIContext.open(home: global.resolvedHome)
                try Output.json(try await context.run { try await $0.get(.parse(project)) })
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Unregister a project (files on disk are kept).")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Project name or id.")
        var project: String

        func run() async throws {
            try await failing {
                let context = try await CLIContext.open(home: global.resolvedHome)
                try Output.json(try await context.run { try await $0.remove(.parse(project)) })
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
                let context = try await CLIContext.open(home: global.resolvedHome)
                let workspace = try await context.run { try await $0.workspace(.parse(project)) }
                try Output.json(workspace.boards.sorted { $0.position < $1.position }.map(BoardResponse.init))
            }
        }
    }
}

extension StorageKind: ExpressibleByArgument {}
