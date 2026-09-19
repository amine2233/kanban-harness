//! JSON file backend for the project registry: versioned envelope, atomic writes.

mod json_store;

pub use json_store::{JsonProjectStore, REGISTRY_VERSION};
