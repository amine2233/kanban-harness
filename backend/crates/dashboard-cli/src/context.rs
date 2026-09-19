use dashboard_persistence_json::JsonProjectStore;
use dashboard_service::ProjectService;
use std::path::PathBuf;
use std::sync::Arc;

pub const REGISTRY_FILE: &str = "projects.json";

pub fn home_dir(explicit: Option<PathBuf>) -> anyhow::Result<PathBuf> {
    if let Some(dir) = explicit {
        return Ok(dir);
    }
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::home_dir().map(|h| h.join(".config")))
        .ok_or_else(|| anyhow::anyhow!("cannot determine home directory; pass --home"))?;
    Ok(base.join("mvp-dashboard"))
}

pub fn service(home: Option<PathBuf>) -> anyhow::Result<Arc<ProjectService>> {
    let store = JsonProjectStore::new(home_dir(home)?.join(REGISTRY_FILE));
    Ok(Arc::new(ProjectService::new(Arc::new(store))))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_home_dir_prefers_explicit_value() {
        let dir = home_dir(Some(PathBuf::from("/explicit"))).unwrap();
        assert_eq!(dir, PathBuf::from("/explicit"));
    }

    #[test]
    fn test_home_dir_defaults_under_config_dir() {
        let dir = home_dir(None).unwrap();
        assert!(dir.ends_with("mvp-dashboard"), "{}", dir.display());
    }
}
