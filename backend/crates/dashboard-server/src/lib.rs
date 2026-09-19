//! HTTP surface: a project registry API plus, per project, the full
//! `kanban-server` REST API mounted under `/api/projects/{id}/kanban`.

pub mod app;
pub mod error;
pub mod state;

pub mod routes {
    pub mod kanban;
    pub mod projects;
}

use std::net::SocketAddr;
use std::path::PathBuf;

pub async fn serve(
    addr: SocketAddr,
    state: state::AppState,
    static_dir: Option<PathBuf>,
) -> std::io::Result<()> {
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(addr = %listener.local_addr()?, "dashboard-server listening");
    axum::serve(listener, app::router(state, static_dir)).await
}
