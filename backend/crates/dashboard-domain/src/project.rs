use crate::error::{DomainError, DomainResult};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use uuid::Uuid;

pub const MAX_NAME_LEN: usize = 64;

/// Which kanban-rs store format lives inside the project folder.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum StorageKind {
    #[default]
    Json,
    Sqlite,
}

impl StorageKind {
    pub fn file_name(self) -> &'static str {
        match self {
            StorageKind::Json => "kanban.json",
            StorageKind::Sqlite => "kanban.sqlite",
        }
    }
}

impl std::str::FromStr for StorageKind {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "json" => Ok(StorageKind::Json),
            "sqlite" => Ok(StorageKind::Sqlite),
            other => Err(format!(
                "unknown storage kind '{other}' (expected json or sqlite)"
            )),
        }
    }
}

/// A registered project: a folder on this machine holding a kanban-rs workspace file.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Project {
    pub id: Uuid,
    pub name: String,
    pub path: PathBuf,
    #[serde(default)]
    pub storage: StorageKind,
    pub created_at: DateTime<Utc>,
}

impl Project {
    pub fn new(name: &str, path: &Path, storage: StorageKind) -> DomainResult<Self> {
        let name = Self::validate_name(name)?;
        if !path.is_absolute() {
            return Err(DomainError::RelativePath(path.to_path_buf()));
        }
        Ok(Self {
            id: Uuid::new_v4(),
            name,
            path: path.to_path_buf(),
            storage,
            created_at: Utc::now(),
        })
    }

    pub fn data_file(&self) -> PathBuf {
        self.path.join(self.storage.file_name())
    }

    fn validate_name(name: &str) -> DomainResult<String> {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            return Err(DomainError::EmptyName);
        }
        if trimmed.chars().count() > MAX_NAME_LEN {
            return Err(DomainError::NameTooLong(MAX_NAME_LEN));
        }
        Ok(trimmed.to_string())
    }
}

/// How callers address a project: by id or by name, the way kanban-rs accepts UUIDs or names.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProjectRef {
    Id(Uuid),
    Name(String),
}

impl ProjectRef {
    pub fn parse(input: &str) -> Self {
        match Uuid::parse_str(input) {
            Ok(id) => ProjectRef::Id(id),
            Err(_) => ProjectRef::Name(input.to_string()),
        }
    }

    pub fn matches(&self, project: &Project) -> bool {
        match self {
            ProjectRef::Id(id) => project.id == *id,
            ProjectRef::Name(name) => project.name.eq_ignore_ascii_case(name),
        }
    }
}

impl std::fmt::Display for ProjectRef {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProjectRef::Id(id) => write!(f, "{id}"),
            ProjectRef::Name(name) => write!(f, "{name}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn abs() -> PathBuf {
        if cfg!(windows) {
            PathBuf::from(r"C:\projects\demo")
        } else {
            PathBuf::from("/projects/demo")
        }
    }

    #[test]
    fn test_new_with_valid_input_trims_name() -> DomainResult<()> {
        let project = Project::new("  Demo  ", &abs(), StorageKind::Json)?;
        assert_eq!(project.name, "Demo");
        assert_eq!(project.path, abs());
        Ok(())
    }

    #[test]
    fn test_new_with_blank_name_returns_empty_name() {
        let err = Project::new("   ", &abs(), StorageKind::Json).unwrap_err();
        assert_eq!(err, DomainError::EmptyName);
    }

    #[test]
    fn test_new_with_too_long_name_returns_name_too_long() {
        let name = "x".repeat(MAX_NAME_LEN + 1);
        let err = Project::new(&name, &abs(), StorageKind::Json).unwrap_err();
        assert_eq!(err, DomainError::NameTooLong(MAX_NAME_LEN));
    }

    #[test]
    fn test_new_with_relative_path_returns_relative_path() {
        let err = Project::new("Demo", Path::new("relative/dir"), StorageKind::Json).unwrap_err();
        assert_eq!(err, DomainError::RelativePath("relative/dir".into()));
    }

    #[test]
    fn test_data_file_uses_storage_file_name() -> DomainResult<()> {
        let json = Project::new("A", &abs(), StorageKind::Json)?;
        let sqlite = Project::new("B", &abs(), StorageKind::Sqlite)?;
        assert_eq!(json.data_file(), abs().join("kanban.json"));
        assert_eq!(sqlite.data_file(), abs().join("kanban.sqlite"));
        Ok(())
    }

    #[test]
    fn test_storage_kind_parses_known_values_and_rejects_unknown() {
        assert_eq!("json".parse::<StorageKind>(), Ok(StorageKind::Json));
        assert_eq!("sqlite".parse::<StorageKind>(), Ok(StorageKind::Sqlite));
        assert!("yaml".parse::<StorageKind>().is_err());
    }

    #[test]
    fn test_storage_kind_serializes_snake_case() {
        assert_eq!(
            serde_json::to_string(&StorageKind::Sqlite).unwrap(),
            "\"sqlite\""
        );
    }

    #[test]
    fn test_project_deserializes_without_storage_field_as_json() {
        let raw = r#"{"id":"6f1c1c1e-2b0c-4b7c-9d3a-1c2b3c4d5e6f","name":"Legacy","path":"/p","created_at":"2026-01-01T00:00:00Z"}"#;
        let project: Project = serde_json::from_str(raw).unwrap();
        assert_eq!(project.storage, StorageKind::Json);
    }

    #[test]
    fn test_project_ref_parse_detects_uuid_and_falls_back_to_name() {
        let id = Uuid::new_v4();
        assert_eq!(ProjectRef::parse(&id.to_string()), ProjectRef::Id(id));
        assert_eq!(ProjectRef::parse("demo"), ProjectRef::Name("demo".into()));
    }

    #[test]
    fn test_project_ref_matches_by_id_and_case_insensitive_name() -> DomainResult<()> {
        let project = Project::new("Demo", &abs(), StorageKind::Json)?;
        assert!(ProjectRef::Id(project.id).matches(&project));
        assert!(ProjectRef::Name("DEMO".into()).matches(&project));
        assert!(!ProjectRef::Name("Other".into()).matches(&project));
        assert!(!ProjectRef::Id(Uuid::new_v4()).matches(&project));
        Ok(())
    }
}
