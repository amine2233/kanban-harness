use std::path::PathBuf;
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum DomainError {
    #[error("project name must not be empty")]
    EmptyName,
    #[error("project name exceeds {0} characters")]
    NameTooLong(usize),
    #[error("project path must be absolute: {0}")]
    RelativePath(PathBuf),
    #[error("a project named '{0}' already exists")]
    DuplicateName(String),
    #[error("a project already uses the path {0}")]
    DuplicatePath(PathBuf),
    #[error("project not found: {0}")]
    NotFound(String),
    #[error("project id not found: {0}")]
    IdNotFound(Uuid),
}

pub type DomainResult<T> = Result<T, DomainError>;
