use crate::error::{AppError, AppJson};
use crate::state::AppState;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use dashboard_domain::{Project, ProjectRef, StorageKind};
use serde::Deserialize;
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct CreateProjectRequest {
    pub name: String,
    pub path: PathBuf,
    #[serde(default)]
    pub storage: StorageKind,
}

async fn list_projects(State(state): State<AppState>) -> Result<Json<Vec<Project>>, AppError> {
    Ok(Json(state.projects.list().await?))
}

async fn create_project(
    State(state): State<AppState>,
    AppJson(req): AppJson<CreateProjectRequest>,
) -> Result<(StatusCode, Json<Project>), AppError> {
    let project = state
        .projects
        .add(&req.name, &req.path, req.storage)
        .await?;
    Ok((StatusCode::CREATED, Json(project)))
}

async fn get_project(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Project>, AppError> {
    Ok(Json(state.projects.get(&ProjectRef::Id(id)).await?))
}

async fn delete_project(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    state.projects.remove(&ProjectRef::Id(id)).await?;
    state.close_workspace(id).await;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/projects", get(list_projects).post(create_project))
        .route(
            "/api/projects/{id}",
            get(get_project).delete(delete_project),
        )
}
