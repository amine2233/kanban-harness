use crate::error::PersistenceResult;
use async_trait::async_trait;
use dashboard_domain::Project;

#[async_trait]
pub trait ProjectStore: Send + Sync {
    /// Returns every persisted project; an absent store yields an empty list.
    async fn load(&self) -> PersistenceResult<Vec<Project>>;

    /// Replaces the persisted list atomically.
    async fn save(&self, projects: &[Project]) -> PersistenceResult<()>;
}
