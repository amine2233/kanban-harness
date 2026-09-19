//! Storage abstraction for the project registry. Backends only load and save
//! the list of projects; invariants live in `dashboard_domain::ProjectRegistry`.

mod error;
mod memory;
mod store;

pub mod contract;

pub use error::{PersistenceError, PersistenceResult};
pub use memory::InMemoryProjectStore;
pub use store::ProjectStore;
