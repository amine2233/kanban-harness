use crate::context;
use dashboard_server::state::AppState;
use std::net::SocketAddr;
use std::path::PathBuf;

pub async fn handle(
    home: Option<PathBuf>,
    addr: &str,
    static_dir: Option<PathBuf>,
) -> anyhow::Result<()> {
    let socket: SocketAddr = addr
        .parse()
        .map_err(|_| anyhow::anyhow!("invalid bind address '{addr}': expected host:port"))?;
    let state = AppState::new(context::service(home)?);
    dashboard_server::serve(socket, state, static_dir).await?;
    Ok(())
}
