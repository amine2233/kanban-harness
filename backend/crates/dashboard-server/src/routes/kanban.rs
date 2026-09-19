use crate::error::AppError;
use crate::state::AppState;
use axum::body::Body;
use axum::extract::{Path, Request, State};
use axum::http::Uri;
use axum::response::{IntoResponse, Response};
use axum::routing::any;
use axum::Router;
use tower::ServiceExt;
use uuid::Uuid;

/// Forwards `/api/projects/{id}/kanban/{rest}` to that project's kanban-server
/// router as `/{rest}`, so the upstream REST API (`/v1/boards`, ...) is served
/// unchanged per project. The request is rebuilt rather than reused so this
/// router's path captures don't leak into the upstream `Path` extractors.
async fn proxy(
    State(state): State<AppState>,
    Path((id, rest)): Path<(Uuid, String)>,
    req: Request,
) -> Result<Response, AppError> {
    let router = state.kanban_router(id).await?;
    let (parts, body) = req.into_parts();
    let mut builder = Request::builder()
        .method(parts.method)
        .uri(rewrite(&parts.uri, &rest));
    if let Some(headers) = builder.headers_mut() {
        *headers = parts.headers;
    }
    let forwarded = builder
        .body(Body::new(body))
        .map_err(|e| AppError::validation(e.to_string()))?;
    router
        .oneshot(forwarded)
        .await
        .map(IntoResponse::into_response)
        .map_err(|never| match never {})
}

fn rewrite(original: &Uri, rest: &str) -> Uri {
    let path = format!("/{}", rest.trim_start_matches('/'));
    let path_and_query = match original.query() {
        Some(query) => format!("{path}?{query}"),
        None => path,
    };
    path_and_query.parse().expect("path built from a valid uri")
}

pub fn router() -> Router<AppState> {
    Router::new().route("/api/projects/{id}/kanban/{*rest}", any(proxy))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rewrite_strips_prefix_and_keeps_query() {
        let original: Uri = "/api/projects/abc/kanban/v1/boards?page=2".parse().unwrap();
        assert_eq!(rewrite(&original, "v1/boards"), "/v1/boards?page=2");
    }

    #[test]
    fn test_rewrite_without_query_yields_plain_path() {
        let original: Uri = "/api/projects/abc/kanban/health".parse().unwrap();
        assert_eq!(rewrite(&original, "/health"), "/health");
    }
}
