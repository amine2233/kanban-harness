//! Behavioural contract every `ProjectStore` must satisfy. Backend crates call
//! `assert_store_contract` from their own tests so all backends share one spec.

use crate::error::PersistenceResult;
use crate::store::ProjectStore;
use dashboard_domain::{Project, StorageKind};
use std::path::PathBuf;

pub fn sample_project(name: &str, dir: &str) -> Project {
    let root = if cfg!(windows) { r"C:\" } else { "/" };
    Project::new(name, &PathBuf::from(root).join(dir), StorageKind::Sqlite).expect("valid")
}

pub async fn assert_store_contract(store: &dyn ProjectStore) -> PersistenceResult<()> {
    assert!(store.load().await?.is_empty(), "fresh store must be empty");

    let projects = vec![sample_project("A", "a"), sample_project("B", "b")];
    store.save(&projects).await?;
    assert_eq!(
        store.load().await?,
        projects,
        "save then load must round-trip"
    );

    let fewer = vec![projects[1].clone()];
    store.save(&fewer).await?;
    assert_eq!(store.load().await?, fewer, "save must replace, not append");

    store.save(&[]).await?;
    assert!(store.load().await?.is_empty(), "saving empty must clear");
    Ok(())
}
