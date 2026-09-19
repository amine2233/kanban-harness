use crate::cli::ProjectAction;
use crate::context;
use crate::output;
use dashboard_domain::ProjectRef;
use kanban_service::api::BoardResponse;
use std::path::{Path, PathBuf};

pub async fn handle(home: Option<PathBuf>, action: ProjectAction) -> anyhow::Result<()> {
    let service = context::service(home)?;
    match action {
        ProjectAction::Add {
            path,
            name,
            storage,
        } => {
            let path = absolute(&path)?;
            let name = name.unwrap_or_else(|| folder_name(&path));
            let project = service.add(&name, &path, storage).await?;
            output::json(&project);
        }
        ProjectAction::List => output::json(&service.list().await?),
        ProjectAction::Show { project } => {
            output::json(&service.get(&ProjectRef::parse(&project)).await?)
        }
        ProjectAction::Remove { project } => {
            output::json(&service.remove(&ProjectRef::parse(&project)).await?)
        }
        ProjectAction::Boards { project } => {
            let boards = service.list_boards(&ProjectRef::parse(&project)).await?;
            let responses: Vec<BoardResponse> = boards.iter().map(BoardResponse::from).collect();
            output::json(&responses);
        }
    }
    Ok(())
}

fn absolute(path: &Path) -> anyhow::Result<PathBuf> {
    Ok(std::path::absolute(path)?)
}

fn folder_name(path: &Path) -> String {
    path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "project".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_folder_name_uses_last_component() {
        assert_eq!(folder_name(Path::new("/a/b/My Project")), "My Project");
    }

    #[test]
    fn test_folder_name_falls_back_for_root() {
        assert_eq!(folder_name(Path::new("/")), "project");
    }

    #[test]
    fn test_absolute_resolves_relative_against_cwd() {
        let resolved = absolute(Path::new("relative")).unwrap();
        assert!(resolved.is_absolute());
        assert!(resolved.ends_with("relative"));
    }
}
