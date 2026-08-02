use thiserror::Error;

#[derive(Debug, Error)]
pub enum VaultCoreError {
    #[error("loro error: {0}")]
    Loro(String),

    #[error("unknown vault item kind: {0}")]
    UnknownKind(String),

    #[error("vault doc is malformed: {0}")]
    Malformed(&'static str),

    #[error("input exceeds byte cap (kind={kind}, limit={limit}, actual={actual})")]
    ByteCap {
        kind: &'static str,
        limit: usize,
        actual: usize,
    },

    #[error("kind mismatch: local={local}, remote={remote}")]
    KindMismatch { local: String, remote: String },

    #[error("snapshot decode failed: {0}")]
    SnapshotDecode(String),

    #[error("delta decode failed: {0}")]
    DeltaDecode(String),

    #[error("unsupported crdt schema version: {0}")]
    UnsupportedVersion(u32),
}

impl From<loro::LoroError> for VaultCoreError {
    fn from(e: loro::LoroError) -> Self {
        VaultCoreError::Loro(e.to_string())
    }
}

impl From<loro::LoroEncodeError> for VaultCoreError {
    fn from(e: loro::LoroEncodeError) -> Self {
        VaultCoreError::Loro(e.to_string())
    }
}

impl From<loro::UpdateTimeoutError> for VaultCoreError {
    fn from(e: loro::UpdateTimeoutError) -> Self {
        VaultCoreError::Loro(e.to_string())
    }
}
