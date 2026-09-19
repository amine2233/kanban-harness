use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use dashboard_persistence::InMemoryProjectStore;
use dashboard_server::{app, state::AppState};
use dashboard_service::ProjectService;
use serde_json::{json, Value};
use std::sync::Arc;
use tempfile::TempDir;
use tower::ServiceExt;

fn state() -> AppState {
    AppState::new(Arc::new(ProjectService::new(Arc::new(
        InMemoryProjectStore::default(),
    ))))
}

async fn send(state: &AppState, method: &str, uri: &str, body: Option<Value>) -> Response {
    let mut builder = Request::builder().method(method).uri(uri);
    let body = match body {
        Some(v) => {
            builder = builder.header("content-type", "application/json");
            Body::from(v.to_string())
        }
        None => Body::empty(),
    };
    app::router(state.clone(), None)
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap()
}

async fn json(response: Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

async fn create_project(state: &AppState, name: &str, dir: &TempDir) -> Value {
    let response = send(
        state,
        "POST",
        "/api/projects",
        Some(json!({ "name": name, "path": dir.path() })),
    )
    .await;
    assert_eq!(response.status(), StatusCode::CREATED);
    json(response).await
}

#[tokio::test(flavor = "multi_thread")]
async fn test_health_returns_ok() {
    let response = send(&state(), "GET", "/api/health", None).await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(json(response).await["status"], "ok");
}

#[tokio::test(flavor = "multi_thread")]
async fn test_list_projects_starts_empty() {
    let response = send(&state(), "GET", "/api/projects", None).await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(json(response).await, json!([]));
}

#[tokio::test(flavor = "multi_thread")]
async fn test_create_project_returns_201_and_lists_it() {
    let dir = TempDir::new().unwrap();
    let state = state();
    let created = create_project(&state, "Demo", &dir).await;
    assert_eq!(created["name"], "Demo");
    assert_eq!(created["storage"], "json");
    let listed = json(send(&state, "GET", "/api/projects", None).await).await;
    assert_eq!(listed.as_array().unwrap().len(), 1);
    assert_eq!(listed[0]["id"], created["id"]);
}

#[tokio::test(flavor = "multi_thread")]
async fn test_create_project_with_invalid_body_returns_400_envelope() {
    let response = send(
        &state(),
        "POST",
        "/api/projects",
        Some(json!({ "name": "x" })),
    )
    .await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert_eq!(json(response).await["code"], "VALIDATION_FAILED");
}

#[tokio::test(flavor = "multi_thread")]
async fn test_create_project_with_relative_path_returns_400() {
    let response = send(
        &state(),
        "POST",
        "/api/projects",
        Some(json!({ "name": "x", "path": "relative" })),
    )
    .await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test(flavor = "multi_thread")]
async fn test_create_duplicate_project_returns_409() {
    let a = TempDir::new().unwrap();
    let b = TempDir::new().unwrap();
    let state = state();
    create_project(&state, "Demo", &a).await;
    let response = send(
        &state,
        "POST",
        "/api/projects",
        Some(json!({ "name": "demo", "path": b.path() })),
    )
    .await;
    assert_eq!(response.status(), StatusCode::CONFLICT);
    assert_eq!(json(response).await["code"], "ALREADY_EXISTS");
}

#[tokio::test(flavor = "multi_thread")]
async fn test_get_unknown_project_returns_404() {
    let uri = format!("/api/projects/{}", uuid::Uuid::new_v4());
    let response = send(&state(), "GET", &uri, None).await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    assert_eq!(json(response).await["code"], "NOT_FOUND");
}

#[tokio::test(flavor = "multi_thread")]
async fn test_delete_project_returns_204_then_404() {
    let dir = TempDir::new().unwrap();
    let state = state();
    let id = create_project(&state, "Demo", &dir).await["id"].clone();
    let uri = format!("/api/projects/{}", id.as_str().unwrap());
    assert_eq!(
        send(&state, "DELETE", &uri, None).await.status(),
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        send(&state, "GET", &uri, None).await.status(),
        StatusCode::NOT_FOUND
    );
    assert!(dir.path().join("kanban.json").is_file());
}

#[tokio::test(flavor = "multi_thread")]
async fn test_kanban_proxy_lists_seeded_board_and_columns() {
    let dir = TempDir::new().unwrap();
    let state = state();
    let id = create_project(&state, "Demo", &dir).await["id"].clone();
    let base = format!("/api/projects/{}/kanban", id.as_str().unwrap());

    let boards = json(send(&state, "GET", &format!("{base}/v1/boards"), None).await).await;
    assert_eq!(boards["total"], 1);
    assert_eq!(boards["items"][0]["name"], "Demo");

    let board_id = boards["items"][0]["id"].as_str().unwrap();
    let columns = json(
        send(
            &state,
            "GET",
            &format!("{base}/v1/boards/{board_id}/columns?page_size=10"),
            None,
        )
        .await,
    )
    .await;
    let names: Vec<_> = columns["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["TODO", "Doing", "Complete"]);
}

#[tokio::test(flavor = "multi_thread")]
async fn test_kanban_proxy_writes_persist_to_project_file() {
    let dir = TempDir::new().unwrap();
    let state = state();
    let id = create_project(&state, "Demo", &dir).await["id"].clone();
    let base = format!("/api/projects/{}/kanban", id.as_str().unwrap());
    let boards = json(send(&state, "GET", &format!("{base}/v1/boards"), None).await).await;
    let board_id = boards["items"][0]["id"].as_str().unwrap().to_string();
    let columns = json(
        send(
            &state,
            "GET",
            &format!("{base}/v1/boards/{board_id}/columns"),
            None,
        )
        .await,
    )
    .await;
    let column_id = columns["items"][0]["id"].as_str().unwrap().to_string();

    let response = send(
        &state,
        "POST",
        &format!("{base}/v1/columns/{column_id}/cards"),
        Some(json!({ "title": "Ship it", "priority": "high" })),
    )
    .await;
    assert_eq!(response.status(), StatusCode::CREATED);
    let card = json(response).await;
    assert_eq!(card["title"], "Ship it");

    let raw = std::fs::read_to_string(dir.path().join("kanban.json")).unwrap();
    assert!(
        raw.contains("Ship it"),
        "card must be saved to the project file"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn test_kanban_proxy_for_unknown_project_returns_404() {
    let uri = format!("/api/projects/{}/kanban/v1/boards", uuid::Uuid::new_v4());
    let response = send(&state(), "GET", &uri, None).await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test(flavor = "multi_thread")]
async fn test_kanban_proxy_after_project_removed_returns_404() {
    let dir = TempDir::new().unwrap();
    let state = state();
    let id = create_project(&state, "Demo", &dir).await["id"].clone();
    let id = id.as_str().unwrap();
    let boards_uri = format!("/api/projects/{id}/kanban/v1/boards");
    assert_eq!(
        send(&state, "GET", &boards_uri, None).await.status(),
        StatusCode::OK
    );
    send(&state, "DELETE", &format!("/api/projects/{id}"), None).await;
    assert_eq!(
        send(&state, "GET", &boards_uri, None).await.status(),
        StatusCode::NOT_FOUND
    );
}
