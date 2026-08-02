use loro::{ExportMode, LoroDoc, LoroValue, UpdateOptions, VersionVector};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

use crate::error::VaultCoreError;
use crate::kind::ItemKind;
use crate::summary::MergeSummary;
use crate::{MAX_BODY_BYTES, MAX_SNAPSHOT_BYTES, MAX_UPDATE_BYTES};

const META_MAP: &str = "meta";
const FRONTMATTER_MAP: &str = "frontmatter";
const BODY_TEXT: &str = "body";
const META_KIND_KEY: &str = "kind";
const META_SCHEMA_VERSION_KEY: &str = "schema_version";
const CURRENT_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultItemSnapshotMeta {
    pub kind: ItemKind,
    pub schema_version: u32,
}

pub struct VaultItemDoc {
    doc: LoroDoc,
}

impl VaultItemDoc {
    pub fn new(kind: ItemKind) -> Result<Self, VaultCoreError> {
        let doc = LoroDoc::new();
        let _ = doc.set_record_timestamp(true);
        let meta = doc.get_map(META_MAP);
        meta.insert(META_KIND_KEY, kind.as_str())?;
        meta.insert(META_SCHEMA_VERSION_KEY, CURRENT_SCHEMA_VERSION as i64)?;
        let _ = doc.get_map(FRONTMATTER_MAP);
        let _ = doc.get_text(BODY_TEXT);
        doc.commit();
        Ok(Self { doc })
    }

    pub fn kind(&self) -> Result<ItemKind, VaultCoreError> {
        let meta = self.doc.get_map(META_MAP);
        let value = meta
            .get(META_KIND_KEY)
            .ok_or(VaultCoreError::Malformed("missing meta.kind"))?;
        let as_string = match value {
            loro::ValueOrContainer::Value(LoroValue::String(s)) => s.to_string(),
            _ => return Err(VaultCoreError::Malformed("meta.kind is not a string")),
        };
        ItemKind::from_str(&as_string)
    }

    pub fn schema_version(&self) -> Result<u32, VaultCoreError> {
        let meta = self.doc.get_map(META_MAP);
        let value = meta
            .get(META_SCHEMA_VERSION_KEY)
            .ok_or(VaultCoreError::Malformed("missing meta.schema_version"))?;
        let n = match value {
            loro::ValueOrContainer::Value(LoroValue::I64(i)) => i,
            _ => return Err(VaultCoreError::Malformed("meta.schema_version not i64")),
        };
        if n < 0 || n > u32::MAX as i64 {
            return Err(VaultCoreError::Malformed("schema_version out of range"));
        }
        let as_u32 = n as u32;
        if as_u32 > CURRENT_SCHEMA_VERSION {
            return Err(VaultCoreError::UnsupportedVersion(as_u32));
        }
        Ok(as_u32)
    }

    pub fn body(&self) -> String {
        self.doc.get_text(BODY_TEXT).to_string()
    }

    pub fn set_body(&self, text: &str) -> Result<(), VaultCoreError> {
        if text.len() > MAX_BODY_BYTES {
            return Err(VaultCoreError::ByteCap {
                kind: "body",
                limit: MAX_BODY_BYTES,
                actual: text.len(),
            });
        }
        let body = self.doc.get_text(BODY_TEXT);
        body.update(text, UpdateOptions::default())?;
        self.doc.commit();
        Ok(())
    }

    pub fn set_frontmatter_string(
        &self,
        key: &str,
        value: &str,
    ) -> Result<(), VaultCoreError> {
        let map = self.doc.get_map(FRONTMATTER_MAP);
        map.insert(key, value)?;
        self.doc.commit();
        Ok(())
    }

    pub fn frontmatter_string(&self, key: &str) -> Result<Option<String>, VaultCoreError> {
        let map = self.doc.get_map(FRONTMATTER_MAP);
        match map.get(key) {
            None => Ok(None),
            Some(loro::ValueOrContainer::Value(LoroValue::String(s))) => {
                Ok(Some(s.to_string()))
            }
            Some(_) => Err(VaultCoreError::Malformed("frontmatter value not string")),
        }
    }

    pub fn encode(&self) -> Result<Vec<u8>, VaultCoreError> {
        let bytes = self.doc.export(ExportMode::Snapshot)?;
        if bytes.len() > MAX_SNAPSHOT_BYTES {
            return Err(VaultCoreError::ByteCap {
                kind: "snapshot",
                limit: MAX_SNAPSHOT_BYTES,
                actual: bytes.len(),
            });
        }
        Ok(bytes)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, VaultCoreError> {
        if bytes.len() > MAX_SNAPSHOT_BYTES {
            return Err(VaultCoreError::ByteCap {
                kind: "snapshot",
                limit: MAX_SNAPSHOT_BYTES,
                actual: bytes.len(),
            });
        }
        let doc = LoroDoc::new();
        doc.import(bytes)
            .map_err(|e| VaultCoreError::SnapshotDecode(e.to_string()))?;
        let _ = doc.set_record_timestamp(true);
        let item = Self { doc };
        let _ = item.kind()?;
        let _ = item.schema_version()?;
        Ok(item)
    }

    pub fn apply_update(&self, update: &[u8]) -> Result<MergeSummary, VaultCoreError> {
        if update.len() > MAX_UPDATE_BYTES {
            return Err(VaultCoreError::ByteCap {
                kind: "update",
                limit: MAX_UPDATE_BYTES,
                actual: update.len(),
            });
        }
        let before_vv = self.doc.oplog_vv();
        let local_frontier_before = frontier_signature(&self.doc);
        self.doc
            .import(update)
            .map_err(|e| VaultCoreError::DeltaDecode(e.to_string()))?;
        self.doc.commit();
        let after_vv = self.doc.oplog_vv();
        let ops_applied = version_vector_difference(&before_vv, &after_vv);
        let peers = new_peers(&before_vv, &after_vv);
        let snapshot_hash = self.snapshot_hash()?;
        let local_frontier = frontier_signature(&self.doc);
        Ok(MergeSummary {
            ops_applied,
            peers,
            new_snapshot_hash: snapshot_hash,
            local_frontier,
            remote_frontier: local_frontier_before,
        })
    }

    pub fn diff_from(&self, peer_snapshot: &[u8]) -> Result<Vec<u8>, VaultCoreError> {
        let peer = VaultItemDoc::decode(peer_snapshot)?;
        let peer_vv = peer.doc.oplog_vv();
        let bytes = self
            .doc
            .export(ExportMode::updates(&peer_vv))
            .map_err(|e| VaultCoreError::Loro(e.to_string()))?;
        if bytes.len() > MAX_UPDATE_BYTES {
            return Err(VaultCoreError::ByteCap {
                kind: "update",
                limit: MAX_UPDATE_BYTES,
                actual: bytes.len(),
            });
        }
        Ok(bytes)
    }

    pub fn snapshot_hash(&self) -> Result<String, VaultCoreError> {
        let bytes = self.encode()?;
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        Ok(hex::encode(hasher.finalize()))
    }

    pub fn peer_id(&self) -> u64 {
        self.doc.peer_id()
    }

    pub fn set_peer_id(&self, peer: u64) -> Result<(), VaultCoreError> {
        self.doc.set_peer_id(peer)?;
        Ok(())
    }

    pub fn change_count(&self) -> usize {
        self.doc.len_changes()
    }
}

fn version_vector_difference(before: &VersionVector, after: &VersionVector) -> u64 {
    let mut total: i64 = 0;
    for (peer, counter_after) in after.iter() {
        let counter_before = before.get(peer).copied().unwrap_or(0);
        let delta = counter_after.saturating_sub(counter_before);
        total = total.saturating_add(delta as i64);
    }
    if total < 0 {
        0
    } else {
        total as u64
    }
}

fn new_peers(before: &VersionVector, after: &VersionVector) -> Vec<u64> {
    let mut peers = BTreeSet::new();
    for (peer, _) in after.iter() {
        if before.get(peer).copied().unwrap_or(0) == 0 {
            peers.insert(*peer);
        }
    }
    peers.into_iter().collect()
}

fn frontier_signature(doc: &LoroDoc) -> String {
    let vv = doc.oplog_vv();
    let mut pairs: Vec<(u64, i32)> = vv.iter().map(|(p, c)| (*p, *c as i32)).collect();
    pairs.sort_by_key(|(p, _)| *p);
    let joined: Vec<String> = pairs
        .into_iter()
        .map(|(p, c)| format!("{:x}:{}", p, c))
        .collect();
    joined.join(",")
}
