use rustler::{Atom, Binary, Encoder, Env, NewBinary, NifResult, Term};
use suchconfig_vault_core::{ItemKind, VaultCoreError, VaultItemDoc};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        unknown_kind,
        malformed,
        byte_cap,
        kind_mismatch,
        snapshot_decode,
        delta_decode,
        unsupported_version,
        loro
    }
}

fn error_atom(e: &VaultCoreError) -> Atom {
    match e {
        VaultCoreError::UnknownKind(_) => atoms::unknown_kind(),
        VaultCoreError::Malformed(_) => atoms::malformed(),
        VaultCoreError::ByteCap { .. } => atoms::byte_cap(),
        VaultCoreError::KindMismatch { .. } => atoms::kind_mismatch(),
        VaultCoreError::SnapshotDecode(_) => atoms::snapshot_decode(),
        VaultCoreError::DeltaDecode(_) => atoms::delta_decode(),
        VaultCoreError::UnsupportedVersion(_) => atoms::unsupported_version(),
        VaultCoreError::Loro(_) => atoms::loro(),
    }
}

fn make_binary<'a>(env: Env<'a>, bytes: &[u8]) -> Binary<'a> {
    let mut nb = NewBinary::new(env, bytes.len());
    nb.as_mut_slice().copy_from_slice(bytes);
    nb.into()
}

#[rustler::nif(name = "nif_new_doc")]
fn nif_new_doc<'a>(env: Env<'a>, kind: String) -> NifResult<Term<'a>> {
    let kind = match ItemKind::from_str(&kind) {
        Ok(k) => k,
        Err(e) => return Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    };
    match VaultItemDoc::new(kind).and_then(|d| d.encode()) {
        Ok(bytes) => Ok((atoms::ok(), make_binary(env, &bytes)).encode(env)),
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_decode_snapshot")]
fn nif_decode_snapshot<'a>(env: Env<'a>, snapshot: Binary<'a>) -> NifResult<Term<'a>> {
    match VaultItemDoc::decode(snapshot.as_slice()) {
        Ok(doc) => match doc.kind() {
            Ok(k) => Ok((atoms::ok(), k.as_str().to_string()).encode(env)),
            Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
        },
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_extract_body")]
fn nif_extract_body<'a>(env: Env<'a>, snapshot: Binary<'a>) -> NifResult<Term<'a>> {
    match VaultItemDoc::decode(snapshot.as_slice()) {
        Ok(doc) => Ok((atoms::ok(), doc.body()).encode(env)),
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_set_body")]
fn nif_set_body<'a>(
    env: Env<'a>,
    snapshot: Binary<'a>,
    body: String,
) -> NifResult<Term<'a>> {
    let doc = match VaultItemDoc::decode(snapshot.as_slice()) {
        Ok(d) => d,
        Err(e) => return Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    };
    if let Err(e) = doc.set_body(&body) {
        return Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env));
    }
    match doc.encode() {
        Ok(bytes) => Ok((atoms::ok(), make_binary(env, &bytes)).encode(env)),
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_apply_update")]
fn nif_apply_update<'a>(
    env: Env<'a>,
    snapshot: Binary<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    let doc = match VaultItemDoc::decode(snapshot.as_slice()) {
        Ok(d) => d,
        Err(e) => return Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    };
    match doc.apply_update(update.as_slice()) {
        Ok(summary) => match doc.encode() {
            Ok(new_snap) => Ok((
                atoms::ok(),
                make_binary(env, &new_snap),
                summary.to_json(),
            )
                .encode(env)),
            Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
        },
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_diff_from")]
fn nif_diff_from<'a>(
    env: Env<'a>,
    current_snapshot: Binary<'a>,
    peer_snapshot: Binary<'a>,
) -> NifResult<Term<'a>> {
    let doc = match VaultItemDoc::decode(current_snapshot.as_slice()) {
        Ok(d) => d,
        Err(e) => return Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    };
    match doc.diff_from(peer_snapshot.as_slice()) {
        Ok(bytes) => Ok((atoms::ok(), make_binary(env, &bytes)).encode(env)),
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_snapshot_hash")]
fn nif_snapshot_hash<'a>(env: Env<'a>, snapshot: Binary<'a>) -> NifResult<Term<'a>> {
    match VaultItemDoc::decode(snapshot.as_slice()) {
        Ok(doc) => match doc.snapshot_hash() {
            Ok(h) => Ok((atoms::ok(), h).encode(env)),
            Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
        },
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_set_frontmatter_string")]
fn nif_set_frontmatter_string<'a>(
    env: Env<'a>,
    snapshot: Binary<'a>,
    key: String,
    value: String,
) -> NifResult<Term<'a>> {
    let doc = match VaultItemDoc::decode(snapshot.as_slice()) {
        Ok(d) => d,
        Err(e) => return Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    };
    if let Err(e) = doc.set_frontmatter_string(&key, &value) {
        return Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env));
    }
    match doc.encode() {
        Ok(bytes) => Ok((atoms::ok(), make_binary(env, &bytes)).encode(env)),
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_frontmatter_string")]
fn nif_frontmatter_string<'a>(
    env: Env<'a>,
    snapshot: Binary<'a>,
    key: String,
) -> NifResult<Term<'a>> {
    match VaultItemDoc::decode(snapshot.as_slice()) {
        Ok(doc) => match doc.frontmatter_string(&key) {
            Ok(opt) => Ok((atoms::ok(), opt).encode(env)),
            Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
        },
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

#[rustler::nif(name = "nif_change_count")]
fn nif_change_count<'a>(env: Env<'a>, snapshot: Binary<'a>) -> NifResult<Term<'a>> {
    match VaultItemDoc::decode(snapshot.as_slice()) {
        Ok(doc) => Ok((atoms::ok(), doc.change_count() as u64).encode(env)),
        Err(e) => Ok((atoms::error(), error_atom(&e), e.to_string()).encode(env)),
    }
}

rustler::init!("Elixir.SuchConfigDesktop.Vault.Crdt");
