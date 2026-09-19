use dashboard_domain::{DomainError, ProjectRef, StorageKind};
use dashboard_persistence::InMemoryProjectStore;
use dashboard_service::{ProjectService, ServiceError, ServiceResult};
use kanban_service::KanbanOperations;
use std::sync::Arc;
use tempfile::TempDir;

fn service() -> ProjectService {
    ProjectService::new(Arc::new(InMemoryProjectStore::default()))
}

#[tokio::test(flavor = "multi_thread")]
async fn test_add_registers_project_and_lists_it() -> ServiceResult<()> {
    let dir = TempDir::new().unwrap();
    let svc = service();
    let project = svc.add("Demo", dir.path(), StorageKind::Json).await?;
    let listed = svc.list().await?;
    assert_eq!(listed, vec![project]);
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn test_add_creates_missing_folder_and_seeds_kanban_json() -> ServiceResult<()> {
    let dir = TempDir::new().unwrap();
    let folder = dir.path().join("new").join("project");
    let svc = service();
    let project = svc.add("Demo", &folder, StorageKind::Json).await?;
    assert!(folder.is_dir());
    assert!(project.data_file().is_file());
    let raw: serde_json::Value =
        serde_json::from_slice(&std::fs::read(project.data_file()).unwrap()).unwrap();
    assert!(raw.get("version").is_some(), "kanban-rs envelope expected");
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn test_add_seeds_one_board_with_template_columns() -> ServiceResult<()> {
    let dir = TempDir::new().unwrap();
    let svc = service();
    svc.add("Demo", dir.path(), StorageKind::Json).await?;
    let (_, ctx) = svc.open_workspace(&ProjectRef::Name("demo".into())).await?;
    let boards = ctx.list_boards()?;
    assert_eq!(boards.len(), 1);
    assert_eq!(boards[0].name, "Demo");
    let columns: Vec<_> = ctx
        .list_columns(boards[0].id)?
        .into_iter()
        .map(|c| c.name)
        .collect();
    assert_eq!(columns, ["TODO", "Doing", "Complete"]);
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn test_add_with_sqlite_storage_seeds_sqlite_file() -> ServiceResult<()> {
    let dir = TempDir::new().unwrap();
    let svc = service();
    let project = svc.add("Demo", dir.path(), StorageKind::Sqlite).await?;
    assert_eq!(project.data_file(), dir.path().join("kanban.sqlite"));
    let header = std::fs::read(project.data_file()).unwrap();
    assert!(header.starts_with(b"SQLite format 3\0"));
    assert_eq!(svc.list_boards(&ProjectRef::Id(project.id)).await?.len(), 1);
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn test_add_existing_workspace_is_not_reseeded() -> ServiceResult<()> {
    let dir = TempDir::new().unwrap();
    let svc = service();
    let project = svc.add("Demo", dir.path(), StorageKind::Json).await?;
    svc.remove(&ProjectRef::Id(project.id)).await?;
    let again = svc.add("Demo again", dir.path(), StorageKind::Json).await?;
    let boards = svc.list_boards(&ProjectRef::Id(again.id)).await?;
    assert_eq!(boards.len(), 1);
    assert_eq!(boards[0].name, "Demo");
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn test_add_duplicate_name_returns_conflict_and_persists_nothing() -> ServiceResult<()> {
    let a = TempDir::new().unwrap();
    let b = TempDir::new().unwrap();
    let svc = service();
    svc.add("Demo", a.path(), StorageKind::Json).await?;
    let err = svc
        .add("demo", b.path(), StorageKind::Json)
        .await
        .unwrap_err();
    assert!(err.is_conflict(), "{err}");
    assert!(!b.path().join("kanban.json").exists());
    assert_eq!(svc.list().await?.len(), 1);
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn test_add_relative_path_returns_domain_error() {
    let svc = service();
    let err = svc
        .add("Demo", std::path::Path::new("relative"), StorageKind::Json)
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        ServiceError::Domain(DomainError::RelativePath(_))
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn test_remove_unregisters_but_keeps_files() -> ServiceResult<()> {
    let dir = TempDir::new().unwrap();
    let svc = service();
    let project = svc.add("Demo", dir.path(), StorageKind::Json).await?;
    let removed = svc.remove(&ProjectRef::Name("Demo".into())).await?;
    assert_eq!(removed.id, project.id);
    assert!(svc.list().await?.is_empty());
    assert!(project.data_file().is_file());
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn test_remove_unknown_returns_not_found() {
    let svc = service();
    let err = svc
        .remove(&ProjectRef::Name("ghost".into()))
        .await
        .unwrap_err();
    assert!(err.is_not_found(), "{err}");
}

#[tokio::test(flavor = "multi_thread")]
async fn test_get_by_id_and_name_return_same_project() -> ServiceResult<()> {
    let dir = TempDir::new().unwrap();
    let svc = service();
    let project = svc.add("Demo", dir.path(), StorageKind::Json).await?;
    assert_eq!(svc.get(&ProjectRef::Id(project.id)).await?, project);
    assert_eq!(svc.get(&ProjectRef::parse("DEMO")).await?, project);
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn test_workspace_changes_are_visible_on_reopen() -> ServiceResult<()> {
    let dir = TempDir::new().unwrap();
    let svc = service();
    let project = svc.add("Demo", dir.path(), StorageKind::Json).await?;
    let reference = ProjectRef::Id(project.id);
    {
        let (_, mut ctx) = svc.open_workspace(&reference).await?;
        ctx.create_board("Second".into(), None)?;
        ctx.save().await?;
    }
    let names: Vec<_> = svc
        .list_boards(&reference)
        .await?
        .into_iter()
        .map(|b| b.name)
        .collect();
    assert_eq!(names, ["Demo", "Second"]);
    Ok(())
}
