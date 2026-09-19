use crate::error::{DomainError, DomainResult};
use crate::project::{Project, ProjectRef};
use uuid::Uuid;

/// In-memory aggregate enforcing registry invariants: unique names (case-insensitive)
/// and unique paths. Persistence layers load/save its contents; they never re-implement rules.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct ProjectRegistry {
    projects: Vec<Project>,
}

impl ProjectRegistry {
    pub fn from_projects(projects: Vec<Project>) -> DomainResult<Self> {
        let mut registry = Self::default();
        for project in projects {
            registry.add(project)?;
        }
        Ok(registry)
    }

    pub fn add(&mut self, project: Project) -> DomainResult<&Project> {
        if let Some(existing) = self.find(&ProjectRef::Name(project.name.clone())) {
            return Err(DomainError::DuplicateName(existing.name.clone()));
        }
        if self.projects.iter().any(|p| p.path == project.path) {
            return Err(DomainError::DuplicatePath(project.path));
        }
        self.projects.push(project);
        Ok(self.projects.last().expect("just pushed"))
    }

    pub fn remove(&mut self, reference: &ProjectRef) -> DomainResult<Project> {
        let index = self
            .projects
            .iter()
            .position(|p| reference.matches(p))
            .ok_or_else(|| Self::not_found(reference))?;
        Ok(self.projects.remove(index))
    }

    pub fn find(&self, reference: &ProjectRef) -> Option<&Project> {
        self.projects.iter().find(|p| reference.matches(p))
    }

    pub fn get(&self, reference: &ProjectRef) -> DomainResult<&Project> {
        self.find(reference)
            .ok_or_else(|| Self::not_found(reference))
    }

    pub fn projects(&self) -> &[Project] {
        &self.projects
    }

    pub fn len(&self) -> usize {
        self.projects.len()
    }

    pub fn is_empty(&self) -> bool {
        self.projects.is_empty()
    }

    pub fn into_projects(self) -> Vec<Project> {
        self.projects
    }

    fn not_found(reference: &ProjectRef) -> DomainError {
        match reference {
            ProjectRef::Id(id) => DomainError::IdNotFound(*id),
            ProjectRef::Name(name) => DomainError::NotFound(name.clone()),
        }
    }
}

impl ProjectRegistry {
    pub fn contains_id(&self, id: Uuid) -> bool {
        self.projects.iter().any(|p| p.id == id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::project::StorageKind;
    use std::path::PathBuf;

    fn project(name: &str, dir: &str) -> Project {
        let root = if cfg!(windows) { r"C:\" } else { "/" };
        Project::new(name, &PathBuf::from(root).join(dir), StorageKind::Json).unwrap()
    }

    #[test]
    fn test_add_distinct_projects_keeps_insertion_order() -> DomainResult<()> {
        let mut registry = ProjectRegistry::default();
        registry.add(project("A", "a"))?;
        registry.add(project("B", "b"))?;
        let names: Vec<_> = registry
            .projects()
            .iter()
            .map(|p| p.name.as_str())
            .collect();
        assert_eq!(names, ["A", "B"]);
        assert_eq!(registry.len(), 2);
        Ok(())
    }

    #[test]
    fn test_add_duplicate_name_case_insensitive_returns_duplicate_name() -> DomainResult<()> {
        let mut registry = ProjectRegistry::default();
        registry.add(project("Demo", "a"))?;
        let err = registry.add(project("demo", "b")).unwrap_err();
        assert_eq!(err, DomainError::DuplicateName("Demo".into()));
        assert_eq!(registry.len(), 1);
        Ok(())
    }

    #[test]
    fn test_add_duplicate_path_returns_duplicate_path() -> DomainResult<()> {
        let mut registry = ProjectRegistry::default();
        let first = project("A", "same");
        let expected_path = first.path.clone();
        registry.add(first)?;
        let err = registry.add(project("B", "same")).unwrap_err();
        assert_eq!(err, DomainError::DuplicatePath(expected_path));
        Ok(())
    }

    #[test]
    fn test_from_projects_rejects_invalid_snapshot() {
        let err =
            ProjectRegistry::from_projects(vec![project("A", "a"), project("a", "b")]).unwrap_err();
        assert_eq!(err, DomainError::DuplicateName("A".into()));
    }

    #[test]
    fn test_remove_by_name_returns_removed_project() -> DomainResult<()> {
        let mut registry = ProjectRegistry::default();
        registry.add(project("A", "a"))?;
        registry.add(project("B", "b"))?;
        let removed = registry.remove(&ProjectRef::Name("a".into()))?;
        assert_eq!(removed.name, "A");
        assert_eq!(registry.len(), 1);
        assert!(registry.find(&ProjectRef::Name("A".into())).is_none());
        Ok(())
    }

    #[test]
    fn test_remove_by_id_returns_removed_project() -> DomainResult<()> {
        let mut registry = ProjectRegistry::default();
        let id = registry.add(project("A", "a"))?.id;
        let removed = registry.remove(&ProjectRef::Id(id))?;
        assert_eq!(removed.id, id);
        assert!(registry.is_empty());
        Ok(())
    }

    #[test]
    fn test_remove_unknown_name_returns_not_found() {
        let mut registry = ProjectRegistry::default();
        let err = registry
            .remove(&ProjectRef::Name("ghost".into()))
            .unwrap_err();
        assert_eq!(err, DomainError::NotFound("ghost".into()));
    }

    #[test]
    fn test_get_unknown_id_returns_id_not_found() {
        let registry = ProjectRegistry::default();
        let id = Uuid::new_v4();
        let err = registry.get(&ProjectRef::Id(id)).unwrap_err();
        assert_eq!(err, DomainError::IdNotFound(id));
    }

    #[test]
    fn test_into_projects_round_trips_through_from_projects() -> DomainResult<()> {
        let mut registry = ProjectRegistry::default();
        registry.add(project("A", "a"))?;
        registry.add(project("B", "b"))?;
        let rebuilt = ProjectRegistry::from_projects(registry.clone().into_projects())?;
        assert_eq!(rebuilt, registry);
        assert!(rebuilt.contains_id(registry.projects()[0].id));
        Ok(())
    }
}
