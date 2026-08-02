#![deny(unsafe_code)]

pub mod doc;
pub mod error;
pub mod kind;
pub mod summary;

pub use doc::VaultItemDoc;
pub use error::VaultCoreError;
pub use kind::ItemKind;
pub use summary::MergeSummary;

pub const MAX_SNAPSHOT_BYTES: usize = 8 * 1024 * 1024;
pub const MAX_UPDATE_BYTES: usize = 4 * 1024 * 1024;
pub const MAX_BODY_BYTES: usize = 1 * 1024 * 1024;
