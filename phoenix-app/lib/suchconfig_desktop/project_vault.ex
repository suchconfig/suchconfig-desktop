defmodule SuchConfigDesktop.ProjectVault do
  @moduledoc """
  Application boundary for Project Vault (folders, secure items, archives).

  Authoritative vault data lives in SQLite via `SuchConfigDesktop.EnvManager`.
  User-visible filesystem paths are not the source of truth for vault content.
  Filesystem interaction is explicit export (and future unpack-to-folder) plus
  optional reveal of paths that already exist on disk (Tauri), never silent
  mirroring of the vault into arbitrary directories.

  Archive packing, previewing, and import routing is delegated to
  `SuchConfigDesktop.ProjectVault.Archive`. Merge audit rows are written here
  on successful operations; insert failures are swallowed so audit never
  blocks user flows.

  CRDT-backed `vault_items` rows are queried here; encode/merge of snapshots
  uses `SuchConfigDesktop.Vault.Crdt` when `feature_enabled?/0` is true.
  """

  import Ecto.Query, warn: false

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.EnvManager
  alias SuchConfigDesktop.ProjectVault.Archive
  alias SuchConfigDesktop.ProjectVault.BrokerCredentials
  alias SuchConfigDesktop.ProjectVault.BrokerFrontmatter
  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter
  alias SuchConfigDesktop.ProjectVault.VaultItemTags
  alias SuchConfigDesktop.ProjectVault.VaultItemTags
  alias SuchConfigDesktop.EnvManager.ProjectFolder
  alias SuchConfigDesktop.Vault.Item
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktop.Vault.Types
  alias SuchConfigDesktop.VaultMergeAuditEvent
  alias SuchConfigCore.Security.EnvCrypto

  @merge_audit_topic "vault:merge_audit"

  def list_project_folders, do: EnvManager.list_project_folders()

  def get_project_folder!(id), do: EnvManager.get_project_folder!(id)

  def create_project_folder(attrs), do: EnvManager.create_project_folder(attrs)

  def update_project_folder(folder, attrs), do: EnvManager.update_project_folder(folder, attrs)

  def delete_project_folder(folder), do: EnvManager.delete_project_folder(folder)

  def list_notes_by_folder(folder_id), do: EnvManager.list_notes_by_folder(folder_id)

  @doc """
  Returns true when the Rustler CRDT NIF is loaded. When false, callers must
  use legacy secure-note paths only.
  """
  def feature_enabled?, do: Crdt.available?()

  @doc """
  When `false`, `save_vault_item/2` returns `{:error, :vault_item_persistence_disabled}`.
  Defaults to `true`; set via `config :suchconfig_desktop, :vault_item_crdt_persistence, false`
  for CI without a Rust NIF build.
  """
  def vault_item_crdt_persistence_enabled? do
    Application.get_env(:suchconfig_desktop, :vault_item_crdt_persistence, true) == true
  end

  @doc """
  Returns true when the active license stub includes Local Broker (Personal Pro).

  Until a full License module ships, this reads
  `config :suchconfig_desktop, :local_broker_license_enabled`.
  Distinct from `feature_enabled?/0` (CRDT NIF availability).
  """
  def local_broker_license_enabled? do
    Application.get_env(:suchconfig_desktop, :local_broker_license_enabled, false) == true
  end

  @doc """
  Returns true when Broker features may be shown and invoked: license + CRDT persistence.
  """
  def local_broker_enabled? do
    local_broker_license_enabled?() and vault_item_crdt_persistence_enabled?()
  end

  @doc """
  Returns true when the active license stub includes Security Sentinel (Personal Pro).

  Until a full License module ships, this reads
  `config :suchconfig_desktop, :security_sentinel_license_enabled`.
  Distinct from Local Broker; CE / free Public Alpha defaults to false.
  """
  def security_sentinel_license_enabled? do
    Application.get_env(:suchconfig_desktop, :security_sentinel_license_enabled, false) == true
  end

  @doc """
  Returns true when Broker is enabled for a specific project folder.
  Requires `local_broker_enabled?/0` and the folder's `broker_enabled` flag.
  """
  def project_broker_enabled?(folder_id) when is_integer(folder_id) do
    local_broker_enabled?() and
      case Repo.get(ProjectFolder, folder_id) do
        %ProjectFolder{broker_enabled: true} -> true
        _ -> false
      end
  end

  def project_broker_enabled?(_), do: false

  @doc """
  Returns the Broker scope manifest fragment for a project folder.

  Keys: `:folder_id`, `:enabled`, `:scope_id`, `:allowed_domains`, `:services`.
  """
  def broker_scope_for_folder(folder_id) when is_integer(folder_id) do
    case Repo.get(ProjectFolder, folder_id) do
      nil ->
        {:error, :not_found}

      %ProjectFolder{} = folder ->
        {:ok,
         %{
           folder_id: folder.id,
           enabled: folder.broker_enabled == true,
           scope_id: folder.broker_scope_id || "",
           allowed_domains: folder.broker_allowed_domains || "",
           services: parse_broker_services(folder.broker_services)
         }}
    end
  end

  def broker_scope_for_folder(_), do: {:error, :invalid_folder}

  @doc """
  Parses a comma-separated domain allowlist into normalized host strings.
  """
  def parse_broker_allowed_domains(raw) when is_binary(raw) do
    raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.downcase/1)
  end

  def parse_broker_allowed_domains(_), do: []

  @doc """
  Parses broker service rules JSON into a list of maps.
  """
  def parse_broker_services(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, list} when is_list(list) ->
        list
        |> Enum.map(&normalize_service_map/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  def parse_broker_services(list) when is_list(list) do
    list
    |> Enum.map(&normalize_service_map/1)
    |> Enum.reject(&is_nil/1)
  end

  def parse_broker_services(_), do: []

  @doc """
  Encodes service rule maps to JSON for folder persistence.
  """
  def encode_broker_services(services) when is_list(services) do
    services
    |> Enum.map(&normalize_service_map/1)
    |> Enum.reject(&is_nil/1)
    |> Jason.encode!()
  end

  def encode_broker_services(_), do: "[]"

  defp normalize_service_map(%{} = service) do
    name = service |> Map.get("name", Map.get(service, :name, "")) |> to_string() |> String.trim()

    host =
      service
      |> Map.get("host", Map.get(service, :host, ""))
      |> to_string()
      |> String.trim()
      |> String.downcase()

    placeholder =
      service
      |> Map.get("placeholder", Map.get(service, :placeholder, ""))
      |> to_string()
      |> String.trim()

    inject_as =
      service
      |> Map.get("inject_as", Map.get(service, :inject_as, "bearer"))
      |> to_string()
      |> String.trim()
      |> String.downcase()

    inject_as =
      if inject_as in ["bearer", "header", "query"], do: inject_as, else: "bearer"

    if name != "" and host != "" and placeholder != "" do
      %{
        "name" => name,
        "host" => host,
        "placeholder" => placeholder,
        "inject_as" => inject_as
      }
    else
      nil
    end
  end

  defp normalize_service_map(_), do: nil

  @doc """
  Default Unix socket path for the local broker runtime.
  """
  def broker_default_socket_path do
    Path.expand("~/.suchconfig/run/broker.sock")
  end

  @doc """
  Run directory for broker manifest files (Mode B handoff).
  """
  def broker_run_dir do
    Path.expand("~/.suchconfig/run")
  end

  @doc """
  Scope manifest file path written by desktop before sidecar spawn.
  """
  def broker_manifest_path(scope_id) when is_binary(scope_id) do
    scope = scope_id |> String.trim()

    if scope == "" do
      nil
    else
      Path.join(broker_run_dir(), "#{scope}.manifest.json")
    end
  end

  @doc """
  Credential map for scope manifest export from CRDT vault items.

  Requires decrypt password. Returns placeholder => secret for broker-enabled items.
  """
  def broker_scope_manifest_credentials(folder_id, password)
      when is_integer(folder_id) and is_binary(password) and password != "" do
    BrokerCredentials.credentials_map(folder_id, password)
    |> normalize_broker_credentials_map()
  end

  def broker_scope_manifest_credentials(folder_id, _password) when is_integer(folder_id) do
    broker_scope_manifest_credentials_legacy(folder_id)
  end

  defp broker_scope_manifest_credentials_legacy(_folder_id) do
    Application.get_env(:suchconfig_desktop, :local_broker_dev_credentials, %{})
    |> normalize_broker_credentials_map()
  end

  @doc """
  Lists vault items in a folder that participate in Broker resolution.
  """
  def list_broker_credentials_for_folder(folder_id, password)
      when is_integer(folder_id) and is_binary(password) do
    BrokerCredentials.list_broker_credentials_for_folder(folder_id, password)
  end

  def list_broker_credentials_for_folder(_, _), do: []

  @doc """
  Enables or disables Broker use for a vault item; persists broker frontmatter on the CRDT item.
  """
  def set_vault_item_broker_enabled(%Item{} = item, enabled, opts, password)
      when is_map(opts) and is_binary(password) and password != "" do
    if local_broker_enabled?() do
      do_set_vault_item_broker_enabled(item, enabled, opts, password)
    else
      {:error, :license_local_broker_required}
    end
  end

  def set_vault_item_broker_enabled(_, _, _, _), do: {:error, :invalid_password}

  @doc """
  Reads broker UI state for a vault item from CRDT frontmatter.
  """
  def vault_item_broker_state(%Item{} = item, password) when is_binary(password) do
    frontmatter = BrokerFrontmatter.read_map(item, password)

    %{
      enabled: BrokerFrontmatter.broker_enabled?(frontmatter),
      placeholder: Map.get(frontmatter, BrokerFrontmatter.broker_placeholder_key(), ""),
      credential_kind:
        Map.get(frontmatter, BrokerFrontmatter.broker_credential_kind_key(), "api_key"),
      inject_as: Map.get(frontmatter, BrokerFrontmatter.broker_inject_as_key(), "header"),
      env_enabled_keys:
        frontmatter
        |> Map.get(BrokerFrontmatter.broker_env_enabled_keys_key(), "")
        |> BrokerFrontmatter.parse_env_enabled_keys()
    }
  end

  def vault_item_broker_state(_, _),
    do: %{
      enabled: false,
      placeholder: "",
      credential_kind: "api_key",
      inject_as: "header",
      env_enabled_keys: []
    }

  @doc """
  Writes the scope manifest JSON file for CLI sidecar handoff (Mode B).
  """
  def write_broker_scope_manifest_file(folder_id, password) when is_integer(folder_id) do
    with {:ok, manifest} <- broker_scope_manifest_for_folder(folder_id, password),
         path when is_binary(path) <- broker_manifest_path(manifest.scope_id) do
      File.mkdir_p!(broker_run_dir())
      payload = manifest_to_json_map(manifest)
      File.write!(path, Jason.encode!(payload))
      {:ok, path}
    else
      {:error, _} = error -> error
      _ -> {:error, :scope_id_required}
    end
  end

  def write_broker_scope_manifest_file(_, _), do: {:error, :invalid_folder}

  @doc false
  def manifest_to_json_map(manifest) do
    %{
      "scope_id" => manifest.scope_id,
      "enabled" => manifest.enabled,
      "allowed_domains" => manifest.allowed_domains,
      "folder_id" => manifest.folder_id,
      "credentials" => manifest.credentials,
      "services" => Map.get(manifest, :services, [])
    }
  end

  @doc """
  Builds a v1 scope manifest map for Tauri → CLI handoff (Mode B).

  Requires broker enabled on the folder and a non-empty scope id.
  """
  def broker_scope_manifest_for_folder(folder_id, password \\ nil) do
    if is_integer(folder_id) do
      do_broker_scope_manifest_for_folder(folder_id, password)
    else
      {:error, :invalid_folder}
    end
  end

  defp do_broker_scope_manifest_for_folder(folder_id, password) do
    with {:ok, scope} <- broker_scope_for_folder(folder_id),
         true <- scope.enabled == true,
         scope_id when is_binary(scope_id) <- normalize_broker_string(scope.scope_id) do
      credentials =
        case password do
          pw when is_binary(pw) and pw != "" ->
            broker_scope_manifest_credentials(folder_id, pw)

          _ ->
            broker_scope_manifest_credentials_legacy(folder_id)
        end

      {:ok,
       %{
         scope_id: scope_id,
         enabled: true,
         allowed_domains: parse_broker_allowed_domains(scope.allowed_domains || ""),
         folder_id: scope.folder_id,
         credentials: credentials,
         services: scope.services || []
       }}
    else
      {:error, _} = error ->
        error

      false ->
        {:error, :broker_disabled}

      :__missing__ ->
        {:error, :scope_id_required}

      nil ->
        {:error, :scope_id_required}
    end
  end

  @doc """
  Updates project-level Broker settings on a folder.

  `attrs` may include `:broker_enabled`, `:broker_scope_id`, `:broker_allowed_domains`,
  `:broker_services` (atom or string keys). Requires `local_broker_enabled?/0`.
  """
  def update_project_broker(%ProjectFolder{} = folder, attrs) when is_map(attrs) do
    if local_broker_enabled?() do
      folder
      |> ProjectFolder.changeset(normalize_broker_attrs(attrs))
      |> Repo.update()
    else
      {:error, :license_local_broker_required}
    end
  end

  def update_project_broker(folder_id, attrs) when is_integer(folder_id) and is_map(attrs) do
    case Repo.get(ProjectFolder, folder_id) do
      nil -> {:error, :not_found}
      %ProjectFolder{} = folder -> update_project_broker(folder, attrs)
    end
  end

  def update_project_broker(_, _), do: {:error, :invalid_folder}

  @doc """
  CLI snippet for a project scope (static until suchconfig-cli ships).
  """
  def broker_cli_snippet(scope_id) when is_binary(scope_id) do
    scope = String.trim(scope_id)

    if scope == "" do
      ""
    else
      """
      suchconfig broker start --scope #{scope}
      suchconfig broker discover --scope #{scope}
      suchconfig broker run --scope #{scope} -- <command>
      suchconfig broker start --scope #{scope} --enable-proxy
      suchconfig broker run --scope #{scope} --enable-proxy -- <command>
      """
      |> String.trim()
    end
  end

  def broker_cli_snippet(_), do: ""

  defp normalize_broker_attrs(attrs) do
    enabled = get_attr(attrs, :broker_enabled, "broker_enabled")
    scope_id = get_attr(attrs, :broker_scope_id, "broker_scope_id")
    domains = get_attr(attrs, :broker_allowed_domains, "broker_allowed_domains")
    services = get_attr(attrs, :broker_services, "broker_services")

    %{}
    |> maybe_put(:broker_enabled, normalize_broker_bool(enabled))
    |> maybe_put(:broker_scope_id, normalize_broker_string(scope_id))
    |> maybe_put(:broker_allowed_domains, normalize_broker_string(domains))
    |> maybe_put(:broker_services, normalize_broker_services_attr(services))
  end

  defp normalize_broker_services_attr(nil), do: :__missing__
  defp normalize_broker_services_attr(:__missing__), do: :__missing__

  defp normalize_broker_services_attr(raw) when is_binary(raw) do
    encode_broker_services(parse_broker_services(raw))
  end

  defp normalize_broker_services_attr(list) when is_list(list) do
    encode_broker_services(list)
  end

  defp normalize_broker_services_attr(_), do: :__missing__

  defp get_attr(attrs, atom_key, string_key) do
    Map.get(attrs, atom_key, Map.get(attrs, string_key))
  end

  defp maybe_put(map, _key, :__missing__), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_broker_bool(nil), do: :__missing__
  defp normalize_broker_bool(true), do: true
  defp normalize_broker_bool(false), do: false
  defp normalize_broker_bool("true"), do: true
  defp normalize_broker_bool("false"), do: false
  defp normalize_broker_bool("1"), do: true
  defp normalize_broker_bool("0"), do: false
  defp normalize_broker_bool("on"), do: true
  defp normalize_broker_bool(_), do: :__missing__

  defp normalize_broker_string(nil), do: :__missing__

  defp normalize_broker_string(value) when is_binary(value) do
    value |> String.trim() |> then(fn s -> if s == "", do: nil, else: s end)
  end

  defp normalize_broker_string(_), do: :__missing__

  defp normalize_broker_credentials_map(%{} = credentials) do
    credentials
    |> Enum.reduce(%{}, fn
      {key, value}, acc when is_binary(key) and is_binary(value) ->
        trimmed_key = String.trim(key)
        trimmed_value = String.trim(value)

        if trimmed_key != "" and trimmed_value != "" do
          Map.put(acc, trimmed_key, trimmed_value)
        else
          acc
        end

      _, acc ->
        acc
    end)
  end

  defp normalize_broker_credentials_map(_), do: %{}

  defp do_set_vault_item_broker_enabled(%Item{} = item, enabled, opts, password) do
    with {:ok, body} <- decrypt_vault_item_body(item, password) do
      frontmatter =
        item
        |> BrokerFrontmatter.read_map(password)
        |> Map.merge(broker_frontmatter_from_opts(item, enabled, opts))

      save_vault_item(
        %{
          id: item.id,
          title: item.title,
          kind: item.kind,
          security_mode: item.security_mode,
          project_folder_id: item.project_folder_id,
          body: body,
          frontmatter: frontmatter
        },
        password
      )
    end
  end

  defp broker_frontmatter_from_opts(_item, enabled, opts) do
    %{
      BrokerFrontmatter.broker_enabled_key() => if(enabled, do: "true", else: "false")
    }
    |> put_optional_frontmatter(opts, BrokerFrontmatter.broker_placeholder_key(), [
      :placeholder,
      "placeholder"
    ])
    |> put_optional_frontmatter(opts, BrokerFrontmatter.broker_credential_kind_key(), [
      :credential_kind,
      "credential_kind"
    ])
    |> put_optional_frontmatter(opts, BrokerFrontmatter.broker_inject_as_key(), [
      :inject_as,
      "inject_as"
    ])
    |> put_optional_env_keys(opts)
  end

  defp put_optional_frontmatter(map, opts, frontmatter_key, opt_keys) do
    case fetch_opt(opts, opt_keys) do
      {:ok, value} -> Map.put(map, frontmatter_key, to_string(value))
      :missing -> map
    end
  end

  defp put_optional_env_keys(map, opts) do
    case Map.get(opts, :env_enabled_keys, Map.get(opts, "env_enabled_keys")) do
      keys when is_list(keys) ->
        Map.put(
          map,
          BrokerFrontmatter.broker_env_enabled_keys_key(),
          BrokerFrontmatter.encode_env_enabled_keys(keys)
        )

      raw when is_binary(raw) ->
        Map.put(map, BrokerFrontmatter.broker_env_enabled_keys_key(), raw)

      _ ->
        map
    end
  end

  defp fetch_opt(opts, keys) do
    keys
    |> Enum.find_value(:missing, fn key ->
      case Map.get(opts, key) do
        nil -> nil
        value -> {:ok, value}
      end
    end)
    |> case do
      {:ok, _} = ok -> ok
      _ -> :missing
    end
  end

  @doc """
  Creates or updates a `vault_items` row with an encrypted Loro CRDT snapshot.

  Requires `vault_item_crdt_persistence_enabled?/0`, `feature_enabled?/0` (NIF), and a
  non-empty `password` (global passkey or per-item policy as used elsewhere).

  `attrs` may use atom or string keys: `title`, `kind`, `security_mode`, `project_folder_id`,
  optional `body` (default `""`), optional `id` to update an existing item,
  optional `frontmatter` (string-key map merged into the CRDT frontmatter map).
  """
  def save_vault_item(attrs, password)
      when is_map(attrs) and is_binary(password) and password != "" do
    with :ok <- ensure_vault_item_persistence(),
         {:ok, normalized} <- normalize_vault_item_attrs(attrs),
         :ok <- validate_vault_folder(normalized.project_folder_id),
         {:ok, item} <- persist_vault_item(normalized, password) do
      {:ok, item}
    end
  end

  def save_vault_item(_attrs, _password), do: {:error, :invalid_password}

  @doc """
  Decrypts the stored CRDT snapshot and returns the document body text.
  """
  def decrypt_vault_item_body(%Item{} = item, password)
      when is_binary(password) and password != "" do
    with {:ok, plain} <-
           EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, body} <- Crdt.body(plain) do
      {:ok, body}
    else
      {:error, _} -> {:error, :invalid_password}
    end
  end

  def decrypt_vault_item_body(_item, _password), do: {:error, :invalid_password}

  def list_vault_items_by_folder(folder_id) when is_integer(folder_id) do
    from(i in Item,
      where: i.project_folder_id == ^folder_id,
      order_by: [asc: i.title, asc: i.id]
    )
    |> Repo.all()
  end

  def get_vault_item(id), do: Repo.get(Item, id)

  def get_vault_item!(id), do: Repo.get!(Item, id)

  def delete_vault_item(id) when is_integer(id) do
    case Repo.get(Item, id) do
      nil -> {:error, :not_found}
      %Item{} = item -> Repo.delete(item)
    end
  end

  def delete_vault_item(_), do: {:error, :not_found}

  @doc """
  Reads one frontmatter string from a vault item (requires decrypt password).
  """
  def vault_item_frontmatter(%Item{} = item, password, key)
      when is_binary(password) and is_binary(key) do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, val} <- Crdt.frontmatter_string(plain, key) do
      {:ok, val}
    else
      {:error, _} -> {:error, :invalid_password}
    end
  end

  def vault_item_frontmatter(_, _, _), do: {:error, :invalid_password}

  def vault_item_change_count(%Item{} = item, password) when is_binary(password) do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, count} <- Crdt.change_count(plain) do
      {:ok, count}
    else
      _ -> {:error, :invalid_password}
    end
  end

  def vault_item_change_count(_, _), do: {:error, :invalid_password}

  @doc """
  Copies a legacy secure note into a new CRDT vault item linked to the same file title.
  """
  def upgrade_legacy_note_to_vault_item(note, folder_id, password)
      when is_binary(password) and password != "" do
    with {:ok, raw} <- decrypt_note_raw_content(note, password),
         tags = VaultItemTags.tags_from_note_type(note.note_type),
         attrs <- %{
           title: note.title,
           kind: note_type_to_vault_kind(note.note_type),
           security_mode: note.security_mode || "global_passkey",
           project_folder_id: folder_id,
           body: raw,
           legacy_note_id: note.id,
           frontmatter:
             note.title
             |> LinkedFrontmatter.import_bundle(raw, 0)
             |> VaultItemTags.merge_frontmatter(tags)
         },
         {:ok, item} <- save_vault_item(attrs, password) do
      {:ok, item}
    end
  end

  def recent_merge_audit(limit \\ 10) when is_integer(limit) and limit > 0 do
    from(e in VaultMergeAuditEvent,
      order_by: [desc: e.inserted_at, desc: e.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def merge_audit_pubsub_topic, do: @merge_audit_topic

  def get_note!(id), do: EnvManager.get_note!(id)

  def delete_note(note), do: EnvManager.delete_note(note)

  def create_secure_note(attrs, password), do: EnvManager.create_secure_note(attrs, password)

  def update_secure_note(note, attrs, password),
    do: EnvManager.update_secure_note(note, attrs, password)

  def decrypt_note_raw_content(note, password),
    do: EnvManager.decrypt_note_raw_content(note, password)

  @doc """
  Packs the selected folders into an encrypted `.suchvault` archive and
  appends an `export` merge audit row on success.
  """
  def export_secure_archive(folder_ids, password)
      when is_list(folder_ids) and is_binary(password) do
    case Archive.pack(folder_ids, password) do
      {:ok, _bin} = ok ->
        folder_id = List.first(folder_ids)

        _ =
          record_merge_audit(
            "export",
            %{
              archive_version: 1,
              format: Archive.format(),
              format_version: Archive.format_version(),
              folder_count: length(folder_ids)
            },
            project_folder_id: folder_id
          )

        ok

      other ->
        other
    end
  end

  @doc """
  Legacy one-shot import: every archive folder is routed to `:create_new`
  using the provided `conflict_strategy`. Prefer `import_with_routing/4` for
  UI-driven flows that preview first.
  """
  def import_secure_archive(archive_binary, password, conflict_strategy)
      when is_binary(archive_binary) and is_binary(password) do
    strategy = normalize_conflict_strategy(conflict_strategy)

    with {:ok, preview} <- Archive.preview(archive_binary, password) do
      routing =
        preview.folders
        |> Enum.map(fn folder -> {folder.index, :create_new} end)
        |> Map.new()

      case Archive.apply_import(archive_binary, password, routing, strategy, []) do
        {:ok, summary} ->
          _ =
            record_merge_audit("import", %{
              archive_version: 1,
              format: preview.format,
              format_version: preview.format_version,
              conflict_strategy: to_string(strategy),
              imported_folder_count: summary.created + summary.merged,
              folder_routing_summary: %{
                created: summary.created,
                merged: summary.merged,
                skipped: summary.skipped,
                notes_imported: summary.notes_imported
              }
            })

          {:ok, Enum.reverse(summary.folders)}

        other ->
          other
      end
    end
  end

  @doc """
  Decrypts an archive and returns a preview struct without touching the DB.
  Used by LiveView to render the import routing UI.
  """
  def preview_archive(archive_binary, password)
      when is_binary(archive_binary) and is_binary(password) do
    Archive.preview(archive_binary, password)
  end

  @doc """
  Applies the archive using the supplied per-folder routing map. Writes an
  `import` merge audit row on success.

  Optional `opts` include `:vault_password` for decrypting and merging CRDT
  `vault_items` on import when an item with the same title already exists.
  """
  def import_with_routing(archive_binary, password, routing, conflict_strategy),
    do: import_with_routing(archive_binary, password, routing, conflict_strategy, [])

  def import_with_routing(archive_binary, password, routing, conflict_strategy, opts)
      when is_binary(archive_binary) and is_binary(password) and is_map(routing) and is_list(opts) do
    strategy = normalize_conflict_strategy(conflict_strategy)

    with {:ok, preview} <- Archive.preview(archive_binary, password),
         {:ok, summary} <-
           Archive.apply_import(archive_binary, password, routing, strategy, opts) do
      _ =
        record_merge_audit("import", %{
          archive_version: 1,
          format: preview.format,
          format_version: preview.format_version,
          conflict_strategy: to_string(strategy),
          imported_folder_count: summary.created + summary.merged,
          folder_routing_summary: %{
            created: summary.created,
            merged: summary.merged,
            skipped: summary.skipped,
            notes_imported: summary.notes_imported,
            vault_items_imported: Map.get(summary, :vault_items_imported, 0),
            vault_items_merged: Map.get(summary, :vault_items_merged, 0)
          }
        })

      merged = Map.get(summary, :vault_items_merged, 0)

      if merged > 0 do
        _ =
          record_merge_audit("crdt_merge", %{
            "items_merged" => merged,
            "summary" => "VaultItem CRDT merge on import"
          })
      end

      {:ok, summary}
    end
  end

  def record_merge_audit(operation, metadata, opts \\ [])
      when is_binary(operation) and is_map(metadata) do
    attrs = %{
      operation: operation,
      metadata: Map.merge(%{}, metadata),
      project_folder_id: Keyword.get(opts, :project_folder_id)
    }

    case %VaultMergeAuditEvent{}
         |> VaultMergeAuditEvent.changeset(attrs)
         |> Repo.insert() do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(
          SuchConfigDesktop.PubSub,
          @merge_audit_topic,
          :vault_merge_audit_updated
        )

        :ok

      {:error, _} ->
        :ok
    end
  end

  def format_error(%Ecto.Changeset{} = changeset) do
    case changeset.errors do
      [{field, {message, _opts}} | _] -> "#{field} #{message}"
      _ -> "Validation failed."
    end
  end

  def format_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  def format_error(reason) when is_binary(reason), do: reason
  def format_error(_), do: "Operation failed."

  defp normalize_conflict_strategy(:duplicate), do: :duplicate
  defp normalize_conflict_strategy(:keep_existing), do: :keep_existing
  defp normalize_conflict_strategy(:replace), do: :replace

  defp normalize_conflict_strategy(s) when is_binary(s) do
    case s do
      "duplicate" -> :duplicate
      "keep_existing" -> :keep_existing
      "replace" -> :replace
      _ -> :duplicate
    end
  end

  defp normalize_conflict_strategy(_), do: :duplicate

  defp ensure_vault_item_persistence do
    cond do
      not vault_item_crdt_persistence_enabled?() ->
        {:error, :vault_item_persistence_disabled}

      not feature_enabled?() ->
        {:error, :crdt_unavailable}

      true ->
        :ok
    end
  end

  defp normalize_vault_item_attrs(attrs) do
    title = attrs |> take_attr(:title) |> vault_trim()
    kind = take_attr(attrs, :kind)
    security_mode = take_attr(attrs, :security_mode)
    folder_id = take_attr(attrs, :project_folder_id)
    body = take_attr(attrs, :body) |> vault_default_string()
    id = take_attr(attrs, :id)
    frontmatter = normalize_frontmatter(take_attr(attrs, :frontmatter))
    legacy_note_id = take_attr(attrs, :legacy_note_id)

    with {:ok, id} <- cast_optional_vault_item_id(id),
         true <- title != "",
         {:ok, kind_atom} <- Types.cast_kind(kind),
         {:ok, mode_atom} <- Types.cast_security_mode(security_mode),
         {:ok, folder_id} <- cast_positive_int(folder_id) do
      {:ok,
       %{
         id: id,
         title: title,
         kind: kind_atom |> Atom.to_string(),
         security_mode: mode_atom |> Atom.to_string(),
         project_folder_id: folder_id,
         body: body,
         frontmatter: frontmatter,
         legacy_note_id: legacy_note_id
       }}
    else
      false -> {:error, :invalid_title}
      {:error, _} = e -> e
    end
  end

  defp normalize_frontmatter(nil), do: %{}

  defp normalize_frontmatter(%{} = m),
    do: Map.new(m, fn {k, v} -> {to_string(k), to_string(v)} end)

  defp normalize_frontmatter(_), do: %{}

  defp note_type_to_vault_kind("environment_files"), do: "env_note"
  defp note_type_to_vault_kind(_), do: "generic_note"

  defp cast_optional_vault_item_id(nil), do: {:ok, nil}

  defp cast_optional_vault_item_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp cast_optional_vault_item_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_id}
    end
  end

  defp cast_optional_vault_item_id(_), do: {:error, :invalid_id}

  defp take_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp vault_trim(nil), do: ""
  defp vault_trim(s) when is_binary(s), do: String.trim(s)
  defp vault_trim(s), do: s |> to_string() |> String.trim()

  defp vault_default_string(nil), do: ""
  defp vault_default_string(s) when is_binary(s), do: s
  defp vault_default_string(s), do: to_string(s)

  defp cast_positive_int(nil), do: {:error, :invalid_folder}

  defp cast_positive_int(i) when is_integer(i) and i > 0, do: {:ok, i}

  defp cast_positive_int(i) when is_binary(i) do
    case Integer.parse(i) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_folder}
    end
  end

  defp cast_positive_int(_), do: {:error, :invalid_folder}

  defp validate_vault_folder(folder_id) do
    case Repo.get(ProjectFolder, folder_id) do
      %ProjectFolder{} -> :ok
      nil -> {:error, :invalid_folder}
    end
  end

  defp persist_vault_item(%{id: nil} = n, password) do
    with {:ok, snap} <- Crdt.new_doc(n.kind),
         {:ok, snap} <- Crdt.set_body(snap, n.body),
         {:ok, snap} <- apply_vault_frontmatter(snap, n.frontmatter),
         {:ok, hash} <- Crdt.snapshot_hash(snap),
         {:ok, enc_bin} <- EnvCrypto.encrypt_to_binary(password, snap) do
      %Item{}
      |> Item.changeset(%{
        title: n.title,
        kind: n.kind,
        security_mode: n.security_mode,
        project_folder_id: n.project_folder_id,
        legacy_note_id: n.legacy_note_id,
        crdt_snapshot_encrypted: enc_bin,
        crdt_snapshot_nonce: nil,
        crdt_encryption_version: 1,
        crdt_schema_version: 1,
        crdt_snapshot_hash: hash,
        updated_clock: System.system_time(:millisecond)
      })
      |> Repo.insert()
    else
      {:error, _} ->
        {:error, :encrypt_failed}

      {:error, _, _} ->
        {:error, :crdt_error}
    end
  end

  defp persist_vault_item(%{id: id} = n, password) when is_integer(id) do
    case Repo.get(Item, id) do
      nil ->
        {:error, :not_found}

      %Item{} = item ->
        if item.project_folder_id != n.project_folder_id do
          {:error, :invalid_folder}
        else
          do_update_vault_item(item, n, password)
        end
    end
  end

  defp persist_vault_item(_, _), do: {:error, :invalid_attrs}

  defp apply_vault_frontmatter(snap, fm) when map_size(fm) == 0, do: {:ok, snap}
  defp apply_vault_frontmatter(snap, fm), do: Crdt.apply_frontmatter(snap, fm)

  defp do_update_vault_item(%Item{} = item, n, password) do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, snap} <- Crdt.set_body(plain, n.body),
         {:ok, snap} <- apply_vault_frontmatter(snap, n.frontmatter),
         {:ok, hash} <- Crdt.snapshot_hash(snap),
         {:ok, enc_bin} <- EnvCrypto.encrypt_to_binary(password, snap) do
      item
      |> Item.changeset(%{
        title: n.title,
        kind: n.kind,
        security_mode: n.security_mode,
        crdt_snapshot_encrypted: enc_bin,
        crdt_encryption_version: 1,
        crdt_schema_version: 1,
        crdt_snapshot_hash: hash,
        updated_clock: System.system_time(:millisecond)
      })
      |> Repo.update()
    else
      {:error, :invalid_password_or_payload} ->
        {:error, :invalid_password}

      {:error, _} ->
        {:error, :encrypt_failed}

      {:error, _, _} ->
        {:error, :crdt_error}
    end
  end
end
