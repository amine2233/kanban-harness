//! Application services. Orchestrates the project registry (our persistence)
//! and per-project kanban workspaces (kanban-rs persistence), depending only
//! on traits from the layers below.

mod error;
mod project_service;
mod workspace;

pub use error::{ServiceError, ServiceResult};
pub use project_service::ProjectService;
pub use workspace::{open_workspace, KanbanContext};
