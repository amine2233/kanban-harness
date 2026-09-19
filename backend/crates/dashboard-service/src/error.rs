use thiserror::Error;

#[derive(Debug, Error)]
pub enum ServiceError {
    #[error(transparent)]
    Domain(#[from] dashboard_domain::DomainError),
    #[error(transparent)]
    Persistence(#[from] dashboard_persistence::PersistenceError),
    #[error("kanban workspace error: {0}")]
    Kanban(#[from] kanban_domain::KanbanError),
    #[error("cannot use project folder {path}: {source}")]
    ProjectFolder {
        path: String,
        #[source]
        source: std::io::Error,
    },
}

impl ServiceError {
    pub fn is_not_found(&self) -> bool {
        use dashboard_domain::DomainError;
        matches!(
            self,
            ServiceError::Domain(DomainError::NotFound(_) | DomainError::IdNotFound(_))
        )
    }

    pub fn is_conflict(&self) -> bool {
        use dashboard_domain::DomainError;
        matches!(
            self,
            ServiceError::Domain(DomainError::DuplicateName(_) | DomainError::DuplicatePath(_))
        )
    }
}

pub type ServiceResult<T> = Result<T, ServiceError>;
