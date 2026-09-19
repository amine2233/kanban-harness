use clap::{Parser, Subcommand};
use dashboard_domain::StorageKind;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(
    name = "dashboard",
    version,
    about = "Manage dashboard projects (kanban-rs compatible workspaces) and run the API server"
)]
pub struct Cli {
    /// Directory holding the project registry (projects.json)
    #[arg(long, global = true, env = "MVP_DASHBOARD_HOME")]
    pub home: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Register, list and inspect projects
    #[command(subcommand)]
    Project(ProjectAction),

    /// Run the HTTP API server
    Serve {
        /// Address to bind as host:port
        #[arg(long, env = "MVP_DASHBOARD_ADDR", default_value = "127.0.0.1:5175")]
        addr: String,

        /// Serve a built frontend directory alongside the API
        #[arg(long, value_name = "DIR")]
        static_dir: Option<PathBuf>,
    },
}

#[derive(Subcommand, Debug)]
pub enum ProjectAction {
    /// Register a folder as a project (created and seeded if missing)
    Add {
        /// Folder holding the project's kanban workspace
        path: PathBuf,

        /// Display name; defaults to the folder name
        #[arg(long)]
        name: Option<String>,

        /// Workspace format written into the folder
        #[arg(long, default_value = "json")]
        storage: StorageKind,
    },

    /// List registered projects
    List,

    /// Show one project by name or id
    Show { project: String },

    /// Unregister a project (files on disk are kept)
    Remove { project: String },

    /// List the kanban boards inside a project
    Boards { project: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_project_add_parses_defaults() {
        let cli = Cli::parse_from(["dashboard", "project", "add", "/tmp/demo"]);
        match cli.command {
            Command::Project(ProjectAction::Add {
                path,
                name,
                storage,
            }) => {
                assert_eq!(path, PathBuf::from("/tmp/demo"));
                assert!(name.is_none());
                assert_eq!(storage, StorageKind::Json);
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn test_project_add_accepts_sqlite_storage_and_name() {
        let cli = Cli::parse_from([
            "dashboard",
            "project",
            "add",
            "/tmp/demo",
            "--name",
            "Demo",
            "--storage",
            "sqlite",
        ]);
        match cli.command {
            Command::Project(ProjectAction::Add { name, storage, .. }) => {
                assert_eq!(name.as_deref(), Some("Demo"));
                assert_eq!(storage, StorageKind::Sqlite);
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn test_project_add_rejects_unknown_storage() {
        let result =
            Cli::try_parse_from(["dashboard", "project", "add", "/x", "--storage", "yaml"]);
        assert!(result.is_err());
    }

    #[test]
    fn test_serve_defaults_to_loopback() {
        let cli = Cli::parse_from(["dashboard", "serve"]);
        match cli.command {
            Command::Serve { addr, static_dir } => {
                assert_eq!(addr, "127.0.0.1:5175");
                assert!(static_dir.is_none());
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn test_home_flag_is_global() {
        let cli = Cli::parse_from(["dashboard", "project", "list", "--home", "/tmp/h"]);
        assert_eq!(cli.home, Some(PathBuf::from("/tmp/h")));
    }
}
