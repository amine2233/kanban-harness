use thiserror::Error;

#[derive(Debug, Error)]
pub enum PersistenceError {
    #[error("io error at {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("corrupt registry file {path}: {reason}")]
    Corrupt { path: String, reason: String },
    #[error("unsupported registry version {found} (this build supports {supported})")]
    UnsupportedVersion { found: u32, supported: u32 },
}

pub type PersistenceResult<T> = Result<T, PersistenceError>;
