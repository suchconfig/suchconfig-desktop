defmodule SuchConfigDesktop.Vault do
  @moduledoc """
  Unified Vault namespace for CRDT-backed VaultItems.

  This namespace is the forward-looking boundary for the CRDT era of Project
  Vault. It coexists with `SuchConfigDesktop.ProjectVault` (which keeps
  delegating to `EnvManager` for folders and legacy secure notes) and exposes
  CRDT primitives, type coercion helpers, and the `VaultItem` domain model.

  CRDT operations flow through `SuchConfigDesktop.Vault.Crdt` (Rustler NIF
  over `suchconfig_vault_core`). When the NIF is unavailable (developer
  machines without Rust toolchain, CI fast paths), callers must check
  `SuchConfigDesktop.Vault.Crdt.available?/0` and fall back to the legacy
  encrypted-note path exposed by `ProjectVault`.
  """
end
