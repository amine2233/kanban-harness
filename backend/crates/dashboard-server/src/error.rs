use axum::extract::rejection::JsonRejection;
use axum::extract::{FromRequest, Request};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use dashboard_service::ServiceError;
use serde::Serialize;

/// Same `{code, message}` envelope kanban-server uses, so the frontend has one error shape.
#[derive(Debug, Serialize)]
pub struct AppError {
    #[serde(skip)]
    pub status: StatusCode,
    pub code: &'static str,
    pub message: String,
}

impl AppError {
    pub fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
        }
    }

    pub fn not_found(message: impl Into<String>) -> Self {
        Self::new(StatusCode::NOT_FOUND, "NOT_FOUND", message)
    }

    pub fn validation(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, "VALIDATION_FAILED", message)
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (self.status, Json(self)).into_response()
    }
}

impl From<ServiceError> for AppError {
    fn from(e: ServiceError) -> Self {
        let message = e.to_string();
        if e.is_not_found() {
            return Self::not_found(message);
        }
        if e.is_conflict() {
            return Self::new(StatusCode::CONFLICT, "ALREADY_EXISTS", message);
        }
        match e {
            ServiceError::Domain(_) => Self::validation(message),
            _ => {
                tracing::error!("{message}");
                Self::new(StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL", message)
            }
        }
    }
}

pub struct AppJson<T>(pub T);

impl<T, S> FromRequest<S> for AppJson<T>
where
    Json<T>: FromRequest<S, Rejection = JsonRejection>,
    S: Send + Sync,
{
    type Rejection = AppError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        match Json::<T>::from_request(req, state).await {
            Ok(Json(value)) => Ok(AppJson(value)),
            Err(rejection) => Err(AppError::validation(rejection.body_text())),
        }
    }
}
