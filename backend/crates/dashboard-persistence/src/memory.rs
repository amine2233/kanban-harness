use crate::error::PersistenceResult;
use crate::store::ProjectStore;
use async_trait::async_trait;
use dashboard_domain::Project;
use tokio::sync::RwLock;

/// Ephemeral store for tests and dry runs.
#[derive(Debug, Default)]
pub struct InMemoryProjectStore {
    projects: RwLock<Vec<Project>>,
}

#[async_trait]
impl ProjectStore for InMemoryProjectStore {
    async fn load(&self) -> PersistenceResult<Vec<Project>> {
        Ok(self.projects.read().await.clone())
    }

    async fn save(&self, projects: &[Project]) -> PersistenceResult<()> {
        *self.projects.write().await = projects.to_vec();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_in_memory_store_satisfies_contract() -> PersistenceResult<()> {
        crate::contract::assert_store_contract(&InMemoryProjectStore::default()).await
    }
}
