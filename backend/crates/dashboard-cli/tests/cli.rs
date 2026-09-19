use assert_cmd::Command;
use predicates::prelude::*;
use serde_json::Value;
use tempfile::TempDir;

fn dashboard(home: &TempDir) -> Command {
    let mut cmd = Command::cargo_bin("dashboard").unwrap();
    cmd.arg("--home").arg(home.path());
    cmd
}

fn json_stdout(cmd: &mut Command) -> Value {
    let output = cmd.output().unwrap();
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}

#[test]
fn test_project_list_starts_empty() {
    let home = TempDir::new().unwrap();
    assert_eq!(
        json_stdout(dashboard(&home).args(["project", "list"])),
        Value::Array(vec![])
    );
}

#[test]
fn test_project_add_defaults_name_to_folder_and_seeds_workspace() {
    let home = TempDir::new().unwrap();
    let folder = TempDir::new().unwrap();
    let path = folder.path().join("Alpha Project");
    let created = json_stdout(dashboard(&home).args(["project", "add"]).arg(&path));
    assert_eq!(created["name"], "Alpha Project");
    assert_eq!(created["storage"], "json");
    assert!(path.join("kanban.json").is_file());
    assert!(home.path().join("projects.json").is_file());
}

#[test]
fn test_project_add_with_name_and_sqlite_storage() {
    let home = TempDir::new().unwrap();
    let folder = TempDir::new().unwrap();
    let created = json_stdout(
        dashboard(&home)
            .args(["project", "add", "--name", "Beta", "--storage", "sqlite"])
            .arg(folder.path()),
    );
    assert_eq!(created["name"], "Beta");
    assert!(folder.path().join("kanban.sqlite").is_file());
}

#[test]
fn test_project_add_duplicate_name_fails_with_json_error() {
    let home = TempDir::new().unwrap();
    let a = TempDir::new().unwrap();
    let b = TempDir::new().unwrap();
    json_stdout(
        dashboard(&home)
            .args(["project", "add", "--name", "Dup"])
            .arg(a.path()),
    );
    dashboard(&home)
        .args(["project", "add", "--name", "dup"])
        .arg(b.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("already exists"));
}

#[test]
fn test_project_show_and_remove_by_name_and_id() {
    let home = TempDir::new().unwrap();
    let folder = TempDir::new().unwrap();
    let created = json_stdout(
        dashboard(&home)
            .args(["project", "add", "--name", "Gamma"])
            .arg(folder.path()),
    );
    let id = created["id"].as_str().unwrap();

    let shown = json_stdout(dashboard(&home).args(["project", "show", "gamma"]));
    assert_eq!(shown["id"], id);

    let removed = json_stdout(dashboard(&home).args(["project", "remove", id]));
    assert_eq!(removed["name"], "Gamma");
    assert_eq!(
        json_stdout(dashboard(&home).args(["project", "list"])),
        Value::Array(vec![])
    );
    assert!(
        folder.path().join("kanban.json").is_file(),
        "files are kept"
    );
}

#[test]
fn test_project_remove_unknown_fails() {
    let home = TempDir::new().unwrap();
    dashboard(&home)
        .args(["project", "remove", "ghost"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("not found"));
}

#[test]
fn test_project_boards_lists_seeded_board() {
    let home = TempDir::new().unwrap();
    let folder = TempDir::new().unwrap();
    json_stdout(
        dashboard(&home)
            .args(["project", "add", "--name", "Delta"])
            .arg(folder.path()),
    );
    let boards = json_stdout(dashboard(&home).args(["project", "boards", "Delta"]));
    assert_eq!(boards.as_array().unwrap().len(), 1);
    assert_eq!(boards[0]["name"], "Delta");
}

#[test]
fn test_registry_persists_between_invocations() {
    let home = TempDir::new().unwrap();
    let folder = TempDir::new().unwrap();
    json_stdout(
        dashboard(&home)
            .args(["project", "add", "--name", "Persist"])
            .arg(folder.path()),
    );
    let listed = json_stdout(dashboard(&home).args(["project", "list"]));
    assert_eq!(listed[0]["name"], "Persist");
}

#[test]
fn test_serve_with_invalid_addr_fails() {
    let home = TempDir::new().unwrap();
    dashboard(&home)
        .args(["serve", "--addr", "not-an-addr"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("invalid bind address"));
}
