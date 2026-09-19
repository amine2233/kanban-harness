use async_trait::async_trait;
use dashboard_domain::Project;
use dashboard_persistence::{PersistenceError, PersistenceResult, ProjectStore};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

pub const REGISTRY_VERSION: u32 = 1;

#[derive(Serialize, Deserialize)]
struct Envelope {
    version: u32,
    projects: Vec<Project>,
}

/// Registry stored as a single JSON file. Writes go to a sibling temp file and
/// are renamed into place, so a crash never leaves a half-written registry.
#[derive(Debug, Clone)]
pub struct JsonProjectStore {
    path: PathBuf,
}

impl JsonProjectStore {
    pub fn new(path: impl AsRef<Path>) -> Self {
        Self {
            path: path.as_ref().to_path_buf(),
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    fn io(&self, source: std::io::Error) -> PersistenceError {
        PersistenceError::Io {
            path: self.path.display().to_string(),
            source,
        }
    }

    fn corrupt(&self, reason: impl ToString) -> PersistenceError {
        PersistenceError::Corrupt {
            path: self.path.display().to_string(),
            reason: reason.to_string(),
        }
    }

    fn parse(&self, raw: &[u8]) -> PersistenceResult<Vec<Project>> {
        let envelope: Envelope = serde_json::from_slice(raw).map_err(|e| self.corrupt(e))?;
        if envelope.version > REGISTRY_VERSION {
            return Err(PersistenceError::UnsupportedVersion {
                found: envelope.version,
                supported: REGISTRY_VERSION,
            });
        }
        Ok(envelope.projects)
    }

    fn write_atomically(&self, bytes: &[u8]) -> PersistenceResult<()> {
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| self.io(e))?;
        }
        let tmp = self.path.with_extension("json.tmp");
        std::fs::write(&tmp, bytes).map_err(|e| self.io(e))?;
        std::fs::rename(&tmp, &self.path).map_err(|e| self.io(e))
    }
}

#[async_trait]
impl ProjectStore for JsonProjectStore {
    async fn load(&self) -> PersistenceResult<Vec<Project>> {
        match tokio::fs::read(&self.path).await {
            Ok(raw) => self.parse(&raw),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
            Err(e) => Err(self.io(e)),
        }
    }

    async fn save(&self, projects: &[Project]) -> PersistenceResult<()> {
        let envelope = Envelope {
            version: REGISTRY_VERSION,
            projects: projects.to_vec(),
        };
        let bytes = serde_json::to_vec_pretty(&envelope).map_err(|e| self.corrupt(e))?;
        let store = self.clone();
        tokio::task::spawn_blocking(move || store.write_atomically(&bytes))
            .await
            .map_err(|e| self.corrupt(format!("write task failed: {e}")))?
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dashboard_persistence::contract::{assert_store_contract, sample_project};
    use tempfile::TempDir;

    fn store_in(dir: &TempDir) -> JsonProjectStore {
        JsonProjectStore::new(dir.path().join("nested").join("projects.json"))
    }

    #[tokio::test]
    async fn test_json_store_satisfies_contract() -> PersistenceResult<()> {
        let dir = TempDir::new().unwrap();
        assert_store_contract(&store_in(&dir)).await
    }

    #[tokio::test]
    async fn test_save_creates_missing_parent_directories() -> PersistenceResult<()> {
        let dir = TempDir::new().unwrap();
        let store = store_in(&dir);
        store.save(&[sample_project("A", "a")]).await?;
        assert!(store.path().exists());
        assert!(!store.path().with_extension("json.tmp").exists());
        Ok(())
    }

    #[tokio::test]
    async fn test_save_writes_versioned_envelope() -> PersistenceResult<()> {
        let dir = TempDir::new().unwrap();
        let store = store_in(&dir);
        store.save(&[sample_project("A", "a")]).await?;
        let raw: serde_json::Value =
            serde_json::from_slice(&std::fs::read(store.path()).unwrap()).unwrap();
        assert_eq!(raw["version"], REGISTRY_VERSION);
        assert_eq!(raw["projects"][0]["name"], "A");
        assert_eq!(raw["projects"][0]["storage"], "sqlite");
        Ok(())
    }

    #[tokio::test]
    async fn test_load_missing_file_returns_empty() -> PersistenceResult<()> {
        let dir = TempDir::new().unwrap();
        assert!(store_in(&dir).load().await?.is_empty());
        Ok(())
    }

    #[tokio::test]
    async fn test_load_malformed_json_returns_corrupt() {
        let dir = TempDir::new().unwrap();
        let store = JsonProjectStore::new(dir.path().join("projects.json"));
        std::fs::write(store.path(), b"{ not json").unwrap();
        let err = store.load().await.unwrap_err();
        assert!(matches!(err, PersistenceError::Corrupt { .. }), "{err}");
    }

    #[tokio::test]
    async fn test_load_future_version_returns_unsupported_version() {
        let dir = TempDir::new().unwrap();
        let store = JsonProjectStore::new(dir.path().join("projects.json"));
        std::fs::write(store.path(), br#"{"version": 99, "projects": []}"#).unwrap();
        let err = store.load().await.unwrap_err();
        assert!(
            matches!(
                err,
                PersistenceError::UnsupportedVersion {
                    found: 99,
                    supported: REGISTRY_VERSION
                }
            ),
            "{err}"
        );
    }

    #[tokio::test]
    async fn test_save_overwrites_existing_file_in_place() -> PersistenceResult<()> {
        let dir = TempDir::new().unwrap();
        let store = store_in(&dir);
        store.save(&[sample_project("A", "a")]).await?;
        store.save(&[sample_project("B", "b")]).await?;
        let names: Vec<_> = store.load().await?.into_iter().map(|p| p.name).collect();
        assert_eq!(names, ["B"]);
        Ok(())
    }
}
