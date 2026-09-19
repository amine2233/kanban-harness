mod cli;
mod context;
mod handlers;
mod output;

use clap::Parser;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_writer(std::io::stderr)
        .init();
    let args = cli::Cli::parse();
    if let Err(e) = handlers::run(args).await {
        output::error(&e);
        std::process::exit(1);
    }
}
