use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MergeSummary {
    pub ops_applied: u64,
    pub peers: Vec<u64>,
    pub new_snapshot_hash: String,
    pub local_frontier: String,
    pub remote_frontier: String,
}

impl MergeSummary {
    pub fn empty() -> Self {
        Self {
            ops_applied: 0,
            peers: Vec::new(),
            new_snapshot_hash: String::new(),
            local_frontier: String::new(),
            remote_frontier: String::new(),
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }
}
