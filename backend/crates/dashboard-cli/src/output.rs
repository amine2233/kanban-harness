use serde::Serialize;

pub fn json<T: Serialize>(value: &T) {
    println!(
        "{}",
        serde_json::to_string_pretty(value).expect("serializable output")
    );
}

pub fn error(err: &anyhow::Error) {
    let payload = serde_json::json!({ "error": { "message": format!("{err:#}") } });
    eprintln!("{payload}");
}
