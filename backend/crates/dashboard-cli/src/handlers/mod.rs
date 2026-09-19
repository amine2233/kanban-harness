mod project;
mod serve;

use crate::cli::{Cli, Command};

pub async fn run(args: Cli) -> anyhow::Result<()> {
    match args.command {
        Command::Project(action) => project::handle(args.home, action).await,
        Command::Serve { addr, static_dir } => serve::handle(args.home, &addr, static_dir).await,
    }
}
