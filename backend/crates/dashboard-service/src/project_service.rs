use crate::error::{ServiceError, ServiceResult};
use crate::workspace;
use dashboard_domain::{Project, ProjectRef, ProjectRegistry, StorageKind};
use dashboard_persistence::ProjectStore;
use kanban_service::{Board, KanbanOperations};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Registers project folders and hands out their kanban workspaces.
/// Removing a project only unregisters it; files on disk are never deleted.
pub struct ProjectService {
    store: Arc<dyn ProjectStore>,
    write_lock: Mutex<()>,
}

impl ProjectService {
    pub fn new(store: Arc<dyn ProjectStore>) -> Self {
        Self {
            store,
            write_lock: Mutex::new(()),
        }
    }

    pub async fn list(&self) -> ServiceResult<Vec<Project>> {
        Ok(self.registry().await?.into_projects())
    }

    pub async fn get(&self, reference: &ProjectRef) -> ServiceResult<Project> {
        Ok(self.registry().await?.get(reference)?.clone())
    }

    pub async fn add(
        &self,
        name: &str,
        path: &Path,
        storage: StorageKind,
    ) -> ServiceResult<Project> {
        let _guard = self.write_lock.lock().await;
        let project = Project::new(name, path, storage)?;
        let mut registry = self.registry().await?;
        registry.add(project.clone())?;
        Self::prepare_folder(&project)?;
        workspace::ensure_seeded(&project).await?;
        self.store.save(registry.projects()).await?;
        Ok(project)
    }

    pub async fn remove(&self, reference: &ProjectRef) -> ServiceResult<Project> {
        let _guard = self.write_lock.lock().await;
        let mut registry = self.registry().await?;
        let removed = registry.remove(reference)?;
        self.store.save(registry.projects()).await?;
        Ok(removed)
    }

    pub async fn open_workspace(
        &self,
        reference: &ProjectRef,
    ) -> ServiceResult<(Project, workspace::KanbanContext)> {
        let project = self.get(reference).await?;
        let ctx = workspace::open_workspace(&project).await?;
        Ok((project, ctx))
    }

    pub async fn list_boards(&self, reference: &ProjectRef) -> ServiceResult<Vec<Board>> {
        let (_, ctx) = self.open_workspace(reference).await?;
        Ok(ctx.list_boards()?)
    }

    async fn registry(&self) -> ServiceResult<ProjectRegistry> {
        Ok(ProjectRegistry::from_projects(self.store.load().await?)?)
    }

    fn prepare_folder(project: &Project) -> ServiceResult<()> {
        std::fs::create_dir_all(&project.path).map_err(|source| ServiceError::ProjectFolder {
            path: project.path.display().to_string(),
            source,
        })
    }
}
