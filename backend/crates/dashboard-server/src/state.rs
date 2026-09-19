use crate::error::AppError;
use axum::Router;
use dashboard_domain::ProjectRef;
use dashboard_service::ProjectService;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

/// Project registry service plus one lazily opened kanban-server router per project.
#[derive(Clone)]
pub struct AppState {
    pub projects: Arc<ProjectService>,
    workspaces: Arc<Mutex<HashMap<Uuid, Router>>>,
}

impl AppState {
    pub fn new(projects: Arc<ProjectService>) -> Self {
        Self {
            projects,
            workspaces: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// The kanban REST router for `project_id`, opened on first use and kept
    /// for the server's lifetime so every request shares one `KanbanContext`.
    pub async fn kanban_router(&self, project_id: Uuid) -> Result<Router, AppError> {
        let mut workspaces = self.workspaces.lock().await;
        if let Some(router) = workspaces.get(&project_id) {
            return Ok(router.clone());
        }
        let (project, ctx) = self
            .projects
            .open_workspace(&ProjectRef::Id(project_id))
            .await?;
        let state = kanban_server::state::AppState::new(ctx);
        let locator = project.data_file().display().to_string();
        if let Err(e) =
            kanban_server::watch::watch_for_external_changes(state.clone(), &locator).await
        {
            tracing::warn!(project = %project.name, "external change watching disabled: {e}");
        }
        let router = kanban_server::app::router(state);
        workspaces.insert(project_id, router.clone());
        Ok(router)
    }

    pub async fn close_workspace(&self, project_id: Uuid) {
        self.workspaces.lock().await.remove(&project_id);
    }
}
