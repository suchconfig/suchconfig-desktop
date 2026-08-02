use suchconfig_vault_core::{ItemKind, VaultCoreError, VaultItemDoc, MAX_SNAPSHOT_BYTES};

#[test]
fn new_doc_of_each_kind_encodes_and_decodes_preserving_kind() {
    for kind in ItemKind::all() {
        let doc = VaultItemDoc::new(*kind).expect("construct");
        let bytes = doc.encode().expect("encode");
        let decoded = VaultItemDoc::decode(&bytes).expect("decode");
        assert_eq!(decoded.kind().expect("kind"), *kind);
        assert_eq!(decoded.schema_version().expect("schema"), 1);
    }
}

#[test]
fn body_round_trips_through_snapshot() {
    let doc = VaultItemDoc::new(ItemKind::PromptTemplate).unwrap();
    doc.set_body("You are a pirate assistant.\n").unwrap();
    let bytes = doc.encode().unwrap();
    let decoded = VaultItemDoc::decode(&bytes).unwrap();
    assert_eq!(decoded.body(), "You are a pirate assistant.\n");
}

#[test]
fn frontmatter_string_round_trip() {
    let doc = VaultItemDoc::new(ItemKind::Guideline).unwrap();
    doc.set_frontmatter_string("owner", "security-team").unwrap();
    doc.set_frontmatter_string("tag", "oauth-2.1").unwrap();
    let bytes = doc.encode().unwrap();
    let decoded = VaultItemDoc::decode(&bytes).unwrap();
    assert_eq!(
        decoded.frontmatter_string("owner").unwrap().as_deref(),
        Some("security-team")
    );
    assert_eq!(
        decoded.frontmatter_string("tag").unwrap().as_deref(),
        Some("oauth-2.1")
    );
    assert_eq!(decoded.frontmatter_string("missing").unwrap(), None);
}

#[test]
fn decoding_unknown_snapshot_returns_error() {
    let garbage = b"not-a-loro-snapshot".to_vec();
    let result = VaultItemDoc::decode(&garbage);
    assert!(matches!(result, Err(VaultCoreError::SnapshotDecode(_))));
}

#[test]
fn snapshot_over_cap_is_rejected_on_decode() {
    let huge = vec![0u8; MAX_SNAPSHOT_BYTES + 1];
    let result = VaultItemDoc::decode(&huge);
    assert!(matches!(
        result,
        Err(VaultCoreError::ByteCap { kind: "snapshot", .. })
    ));
}

#[test]
fn body_over_cap_is_rejected() {
    let doc = VaultItemDoc::new(ItemKind::GenericNote).unwrap();
    let big = "a".repeat(suchconfig_vault_core::MAX_BODY_BYTES + 1);
    let result = doc.set_body(&big);
    assert!(matches!(
        result,
        Err(VaultCoreError::ByteCap { kind: "body", .. })
    ));
}

#[test]
fn kind_from_str_rejects_unknown() {
    let result = ItemKind::from_str("not_a_kind");
    assert!(matches!(result, Err(VaultCoreError::UnknownKind(s)) if s == "not_a_kind"));
}

#[test]
fn snapshot_hash_is_stable_for_identical_state() {
    let a = VaultItemDoc::new(ItemKind::EnvNote).unwrap();
    a.set_peer_id(0xAAAA).unwrap();
    a.set_body("DB_URL=postgres://localhost/app\n").unwrap();

    let b = VaultItemDoc::new(ItemKind::EnvNote).unwrap();
    b.set_peer_id(0xAAAA).unwrap();
    b.set_body("DB_URL=postgres://localhost/app\n").unwrap();

    assert_eq!(a.body(), b.body());
}
