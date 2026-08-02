use proptest::prelude::*;
use proptest::test_runner::Config as ProptestConfig;
use suchconfig_vault_core::{ItemKind, VaultItemDoc};

fn new_peer(peer_id: u64, kind: ItemKind) -> VaultItemDoc {
    let doc = VaultItemDoc::new(kind).unwrap();
    doc.set_peer_id(peer_id).unwrap();
    doc
}

#[test]
fn two_peers_converge_after_exchanging_updates() {
    let a = new_peer(1, ItemKind::PromptTemplate);
    let b = new_peer(2, ItemKind::PromptTemplate);

    a.set_body("You are a helpful assistant.").unwrap();
    b.set_body("You write secure code.").unwrap();

    let a_snap = a.encode().unwrap();
    let b_snap = b.encode().unwrap();

    let a_to_b = a.diff_from(&b_snap).unwrap();
    let b_to_a = b.diff_from(&a_snap).unwrap();

    let summary_b = b.apply_update(&a_to_b).unwrap();
    let summary_a = a.apply_update(&b_to_a).unwrap();

    assert_eq!(a.body(), b.body(), "merged text must match (CRDT value convergence)");
    assert!(summary_a.ops_applied > 0);
    assert!(summary_b.ops_applied > 0);
}

#[test]
fn apply_update_is_commutative_across_two_peers() {
    let a1 = new_peer(10, ItemKind::GenericNote);
    let b1 = new_peer(20, ItemKind::GenericNote);
    a1.set_body("alpha").unwrap();
    b1.set_body("beta").unwrap();
    let update_a = a1
        .diff_from(
            &VaultItemDoc::new(ItemKind::GenericNote)
                .unwrap()
                .encode()
                .unwrap(),
        )
        .unwrap();
    let update_b = b1
        .diff_from(
            &VaultItemDoc::new(ItemKind::GenericNote)
                .unwrap()
                .encode()
                .unwrap(),
        )
        .unwrap();

    let left = VaultItemDoc::new(ItemKind::GenericNote).unwrap();
    left.apply_update(&update_a).unwrap();
    left.apply_update(&update_b).unwrap();

    let right = VaultItemDoc::new(ItemKind::GenericNote).unwrap();
    right.apply_update(&update_b).unwrap();
    right.apply_update(&update_a).unwrap();

    assert_eq!(left.body(), right.body());
}

#[test]
fn re_applying_same_update_is_idempotent() {
    let a = new_peer(7, ItemKind::Guideline);
    a.set_body("Revocation policy: 24h.").unwrap();
    let baseline = VaultItemDoc::new(ItemKind::Guideline)
        .unwrap()
        .encode()
        .unwrap();
    let update = a.diff_from(&baseline).unwrap();

    let target = VaultItemDoc::new(ItemKind::Guideline).unwrap();
    let first = target.apply_update(&update).unwrap();
    let mid_hash = target.snapshot_hash().unwrap();
    let second = target.apply_update(&update).unwrap();

    assert_eq!(target.snapshot_hash().unwrap(), mid_hash);
    assert!(first.ops_applied >= second.ops_applied);
}

#[test]
fn password_kind_peers_converge_after_exchanging_updates() {
    let a = new_peer(1, ItemKind::Password);
    let b = new_peer(2, ItemKind::Password);

    a.set_body("placeholder-secret-value").unwrap();
    b.set_body("other-placeholder-secret").unwrap();

    let a_snap = a.encode().unwrap();
    let b_snap = b.encode().unwrap();

    let a_to_b = a.diff_from(&b_snap).unwrap();
    let b_to_a = b.diff_from(&a_snap).unwrap();

    b.apply_update(&a_to_b).unwrap();
    a.apply_update(&b_to_a).unwrap();

    assert_eq!(a.body(), b.body());
}

#[test]
fn corrupted_update_bytes_return_decode_error() {
    let a = new_peer(1, ItemKind::EnvNote);
    let result = a.apply_update(b"not-a-real-update-payload");
    assert!(result.is_err());
}

proptest! {
    #![proptest_config(ProptestConfig {
        cases: 32,
        failure_persistence: None,
        ..ProptestConfig::default()
    })]

    #[test]
    fn order_independent_convergence(
        edits in proptest::collection::vec("[a-z]{1,8}", 2..6)
    ) {
        let base = VaultItemDoc::new(ItemKind::PromptTemplate).unwrap();
        let base_bytes = base.encode().unwrap();

        let peer_a = VaultItemDoc::new(ItemKind::PromptTemplate).unwrap();
        peer_a.set_peer_id(111).unwrap();
        let peer_b = VaultItemDoc::new(ItemKind::PromptTemplate).unwrap();
        peer_b.set_peer_id(222).unwrap();

        for (i, e) in edits.iter().enumerate() {
            if i % 2 == 0 { peer_a.set_body(e).unwrap(); }
            else { peer_b.set_body(e).unwrap(); }
        }

        let a_update = peer_a.diff_from(&base_bytes).unwrap();
        let b_update = peer_b.diff_from(&base_bytes).unwrap();

        let lhs = VaultItemDoc::new(ItemKind::PromptTemplate).unwrap();
        lhs.apply_update(&a_update).unwrap();
        lhs.apply_update(&b_update).unwrap();

        let rhs = VaultItemDoc::new(ItemKind::PromptTemplate).unwrap();
        rhs.apply_update(&b_update).unwrap();
        rhs.apply_update(&a_update).unwrap();

        prop_assert_eq!(lhs.body(), rhs.body());
    }
}
