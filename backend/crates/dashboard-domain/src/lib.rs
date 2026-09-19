//! Pure domain model: no I/O, no async. Everything here is testable offline.

mod error;
mod project;
mod registry;

pub use error::{DomainError, DomainResult};
pub use project::{Project, ProjectRef, StorageKind, MAX_NAME_LEN};
pub use registry::ProjectRegistry;
