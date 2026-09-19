use crate::error::ServiceResult;
use dashboard_domain::Project;
use kanban_service::{AppConfig, KanbanOperations, StoreManager};

pub use kanban_service::KanbanContext;

fn store_manager() -> StoreManager {
    let mut stores = kanban_persistence::StoreRegistry::new();
    let mut backends = kanban_backend::KanbanBackendRegistry::new();
    stores.register(Box::new(kanban_persistence_sqlite::SqliteStoreFactory));
    backends.register(Box::new(kanban_persistence_sqlite::SqliteBackendFactory));
    stores.register(Box::new(kanban_persistence_json::JsonStoreFactory));
    backends.register(Box::new(kanban_persistence_json::JsonBackendFactory));
    StoreManager::new(stores, backends)
}

/// Opens the kanban-rs workspace stored in the project folder. The file is
/// byte-compatible with the `kanban` CLI/TUI, which can open it directly.
pub async fn open_workspace(project: &Project) -> ServiceResult<KanbanContext> {
    let locator = project.data_file().display().to_string();
    let mut config = AppConfig::default();
    let manager = store_manager();
    manager.sync_backend_with_file(&locator, &mut config);
    let backend = manager.make_backend(&locator, &config).await?;
    Ok(KanbanContext::open(backend, config).await?)
}

/// Seeds a first board (named after the project) with kanban-rs' default
/// template columns so a fresh project is immediately usable.
pub async fn ensure_seeded(project: &Project) -> ServiceResult<()> {
    let mut ctx = open_workspace(project).await?;
    if !ctx.list_boards()?.is_empty() {
        return Ok(());
    }
    let board = ctx.create_board(project.name.clone(), None)?;
    for (name, default_status) in kanban_domain::DEFAULT_TEMPLATE_COLUMNS {
        ctx.create_column_from_spec(
            None,
            kanban_domain::NewColumn {
                board_id: board.id,
                name: name.to_string(),
                wip_limit: None,
                default_status,
            },
        )?;
    }
    ctx.save().await?;
    Ok(())
}
