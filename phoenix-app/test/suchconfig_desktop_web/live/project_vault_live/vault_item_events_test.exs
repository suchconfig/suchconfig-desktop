defmodule SuchConfigDesktopWeb.ProjectVaultLive.VaultItemEventsTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.AutoDetect
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultItemEvents

  defp base_socket(overrides \\ %{}) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          flash: %{},
          vault_item_ui_enabled?: true,
          selected_folder_id: nil,
          vault_password: "link-project-pw",
          link_project_preview: nil,
          link_project_scan_path: nil,
          link_project_vault_candidates: [],
          link_project_vault_selected: %{},
          link_project_ai_tooling: nil,
          link_project_scaffold_selected: %{},
          link_project_existing_notes_strategy: "duplicate",
          link_project_stage: :idle,
          link_project_error: nil,
          show_link_project_modal: false
        },
        overrides
      )

    %Phoenix.LiveView.Socket{
      endpoint: SuchConfigDesktopWeb.Endpoint,
      view: SuchConfigDesktopWeb.ProjectVaultLive,
      assigns: assigns
    }
  end

  defp temp_project_dir! do
    dir = Path.join(System.tmp_dir!(), "link_proj_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, ".gitignore"), ".env*\n")
    File.write!(Path.join(dir, ".env"), "API_KEY=from-disk\n")
    File.write!(Path.join(dir, ".cursorrules"), "rules\n")
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp restore_app_env(key, previous) do
    if is_nil(previous) do
      Application.delete_env(:suchconfig_desktop, key)
    else
      Application.put_env(:suchconfig_desktop, key, previous)
    end
  end

  describe "apply_link_project_scan/2" do
    test "moves to preview with candidates and markdown" do
      dir = temp_project_dir!()
      {:ok, project_data} = AutoDetect.scan_disk(dir)

      socket = base_socket(%{show_link_project_modal: true, link_project_stage: :select_path})

      result = VaultItemEvents.apply_link_project_scan(socket, {:ok, project_data})

      assert result.assigns.link_project_stage == :preview
      assert is_binary(result.assigns.link_project_preview)
      assert String.trim(result.assigns.link_project_preview) != ""
      assert result.assigns.link_project_scan_path == dir
      assert length(result.assigns.link_project_vault_candidates) >= 1
      assert Map.get(result.assigns.link_project_vault_selected, ".env", true)
      assert is_map(result.assigns.link_project_ai_tooling)
      assert "Cursor" in result.assigns.link_project_ai_tooling.folder_tags
      assert Map.get(result.assigns.link_project_scaffold_selected, ".cursorignore") == true
    end

    test "python project_data reaches preview without crashing" do
      project_data = %{
        project_type: :python,
        project_name: "broken",
        path: "/tmp/broken",
        files: [%{type: :pyproject, name: "pyproject.toml", scripts: []}],
        dependencies: [],
        scripts: [],
        vault_file_candidates: [
          %{
            relative_path: ".env",
            absolute_path: "/tmp/broken/.env",
            gitignored: true,
            note_type: "environment_files"
          }
        ]
      }

      socket = base_socket()
      result = VaultItemEvents.apply_link_project_scan(socket, {:ok, project_data})

      assert result.assigns.link_project_stage == :preview
      assert is_binary(result.assigns.link_project_preview)
      assert length(result.assigns.link_project_vault_candidates) == 1
      assert Map.get(result.assigns.link_project_vault_selected, ".env")
    end

    test "returns select_path on scan error" do
      socket = base_socket(%{link_project_stage: :scanning})

      result = VaultItemEvents.apply_link_project_scan(socket, {:error, "not a directory"})

      assert result.assigns.link_project_stage == :select_path
      assert result.assigns.link_project_error =~ "not a directory"
    end
  end

  describe "open_link_project_modal/2" do
    test "requires selected folder" do
      {:noreply, socket} = VaultItemEvents.open_link_project_modal(%{}, base_socket())

      assert socket.assigns.error =~ "Select a project folder"
      refute socket.assigns.show_link_project_modal
    end

    test "opens modal when folder selected" do
      folder = project_folder_fixture()

      {:noreply, socket} =
        VaultItemEvents.open_link_project_modal(
          %{},
          base_socket(%{selected_folder_id: folder.id})
        )

      assert socket.assigns.show_link_project_modal
      assert socket.assigns.link_project_stage == :select_path
    end
  end

  describe "link_project_existing_notes_change/2" do
    test "stores overwrite or duplicate strategy" do
      {:noreply, socket} =
        VaultItemEvents.link_project_existing_notes_change(
          %{"existing_notes" => "overwrite"},
          base_socket()
        )

      assert socket.assigns.link_project_existing_notes_strategy == "overwrite"

      {:noreply, cleared} =
        VaultItemEvents.link_project_existing_notes_change(%{"existing_notes" => ""}, socket)

      assert cleared.assigns.link_project_existing_notes_strategy == nil

      {:noreply, from_form} =
        VaultItemEvents.link_project_existing_notes_change(
          %{"_target" => ["existing_notes"], "existing_notes" => "duplicate"},
          socket
        )

      assert from_form.assigns.link_project_existing_notes_strategy == "duplicate"
    end
  end

  describe "link_project_scaffold_toggle/2" do
    test "toggles scaffold selection" do
      socket =
        base_socket(%{
          link_project_scaffold_selected: %{".cursorignore" => true}
        })

      {:noreply, toggled} =
        VaultItemEvents.link_project_scaffold_toggle(%{"path" => ".cursorignore"}, socket)

      assert Map.get(toggled.assigns.link_project_scaffold_selected, ".cursorignore") == false
    end
  end

  describe "link_project_sentinel_change/2" do
    test "stores run sentinel checkbox" do
      {:noreply, checked} =
        VaultItemEvents.link_project_sentinel_change(
          %{"run_sentinel_scan" => "true"},
          base_socket(%{link_project_run_sentinel: false})
        )

      assert checked.assigns.link_project_run_sentinel

      {:noreply, unchecked} =
        VaultItemEvents.link_project_sentinel_change(%{}, checked)

      refute unchecked.assigns.link_project_run_sentinel
    end
  end

  describe "confirm_link_project/2" do
    setup _context do
      if not Crdt.available?() do
        {:skip, "Rustler NIF `vault_crdt` not loaded"}
      else
        :ok
      end
    end

    test "links folder path, creates project details, and imports config vault items" do
      dir = temp_project_dir!()
      folder = project_folder_fixture()
      password = "confirm-link-#{System.unique_integer([:positive])}"

      {:ok, project_data} = AutoDetect.scan_disk(dir)

      scan_socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: password,
          show_link_project_modal: true
        })
        |> then(&VaultItemEvents.apply_link_project_scan(&1, {:ok, project_data}))
        |> then(
          &%{
            &1
            | assigns: Map.put(&1.assigns, :link_project_existing_notes_strategy, "duplicate")
          }
        )

      {:noreply, confirm_socket} =
        VaultItemEvents.confirm_link_project(%{}, scan_socket)

      assert confirm_socket.assigns.show_link_project_modal == false
      assert confirm_socket.assigns.info =~ "Project Details"
      assert confirm_socket.assigns.info =~ "Imported"
      assert confirm_socket.assigns.info =~ "Created"
      assert confirm_socket.assigns.info =~ "AI ignore"
      refute confirm_socket.assigns[:sentinel_scanning]

      updated_folder = ProjectVault.get_project_folder!(folder.id)
      assert updated_folder.linked_project_path == dir
      assert updated_folder.tags =~ "Cursor"
      assert File.regular?(Path.join(dir, ".cursorignore"))

      items = ProjectVault.list_vault_items_by_folder(folder.id)
      assert Enum.any?(items, &(&1.title == ".env" and &1.kind == "env_note"))
      assert Enum.any?(items, &(&1.title == "Project Details" and &1.kind == "guideline"))
    end

    test "starts sentinel when Pro checkbox is checked" do
      previous = Application.get_env(:suchconfig_desktop, :security_sentinel_license_enabled)

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:suchconfig_desktop, :security_sentinel_license_enabled)
        else
          Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, previous)
        end
      end)

      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, true)

      dir = temp_project_dir!()
      folder = project_folder_fixture()
      password = "confirm-sentinel-#{System.unique_integer([:positive])}"
      {:ok, project_data} = AutoDetect.scan_disk(dir)

      scan_socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: password,
          show_link_project_modal: true,
          link_project_run_sentinel: true
        })
        |> then(&VaultItemEvents.apply_link_project_scan(&1, {:ok, project_data}))
        |> then(
          &%{
            &1
            | assigns: Map.put(&1.assigns, :link_project_existing_notes_strategy, "duplicate")
          }
        )

      {:noreply, confirm_socket} = VaultItemEvents.confirm_link_project(%{}, scan_socket)

      assert confirm_socket.assigns.sentinel_scanning == true
      assert confirm_socket.assigns.sentinel_pending_path == dir
      assert confirm_socket.assigns.sentinel_pending_folder_id == folder.id
    end

    test "does not start sentinel when only Broker license is enabled" do
      previous_broker = Application.get_env(:suchconfig_desktop, :local_broker_license_enabled)

      previous_sentinel =
        Application.get_env(:suchconfig_desktop, :security_sentinel_license_enabled)

      on_exit(fn ->
        restore_app_env(:local_broker_license_enabled, previous_broker)
        restore_app_env(:security_sentinel_license_enabled, previous_sentinel)
      end)

      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, false)

      dir = temp_project_dir!()
      folder = project_folder_fixture()
      password = "broker-only-sentinel-#{System.unique_integer([:positive])}"
      {:ok, project_data} = AutoDetect.scan_disk(dir)

      scan_socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: password,
          show_link_project_modal: true,
          link_project_run_sentinel: true
        })
        |> then(&VaultItemEvents.apply_link_project_scan(&1, {:ok, project_data}))
        |> then(
          &%{
            &1
            | assigns: Map.put(&1.assigns, :link_project_existing_notes_strategy, "duplicate")
          }
        )

      {:noreply, confirm_socket} = VaultItemEvents.confirm_link_project(%{}, scan_socket)

      refute confirm_socket.assigns[:sentinel_scanning]
      refute confirm_socket.assigns[:show_sentinel_report_modal]
    end

    test "upserts existing project details vault item" do
      dir = temp_project_dir!()
      folder = project_folder_fixture()
      password = "upsert-pd-#{System.unique_integer([:positive])}"

      assert {:ok, existing} =
               ProjectVault.save_vault_item(
                 %{
                   title: "Project Details",
                   kind: "guideline",
                   security_mode: "global_passkey",
                   project_folder_id: folder.id,
                   body: "old body"
                 },
                 password
               )

      preview = "# Updated\n\nNew content."
      candidates = AutoDetect.scan_disk(dir) |> elem(1) |> Map.get(:vault_file_candidates, [])

      socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: password,
          link_project_preview: preview,
          link_project_scan_path: dir,
          link_project_vault_candidates: candidates,
          link_project_vault_selected: Map.new(candidates, &{&1.relative_path, true}),
          link_project_existing_notes_strategy: "duplicate"
        })

      {:noreply, _} = VaultItemEvents.confirm_link_project(%{}, socket)

      items = ProjectVault.list_vault_items_by_folder(folder.id)
      pd_items = Enum.filter(items, &(&1.title == "Project Details"))
      assert length(pd_items) == 1
      assert hd(pd_items).id == existing.id
      assert {:ok, body} = ProjectVault.decrypt_vault_item_body(hd(pd_items), password)
      assert body =~ "New content."
    end

    test "prompts for passkey when vault password missing" do
      folder = project_folder_fixture()

      socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: "",
          link_project_preview: "# x",
          link_project_scan_path: "/tmp/x",
          link_project_stage: :preview,
          show_link_project_modal: true
        })

      {:noreply, result} = VaultItemEvents.confirm_link_project(%{}, socket)

      assert result.assigns.show_global_passkey_modal
      refute result.assigns.show_link_project_modal
      assert result.assigns.pending_unlock_action == :confirm_link_project
    end

    test "requires existing notes strategy before confirm when folder has items" do
      folder = project_folder_fixture()
      dir = temp_project_dir!()
      {:ok, project_data} = AutoDetect.scan_disk(dir)

      scan_socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: "strategy-pw",
          show_link_project_modal: true,
          vault_items: [%{id: 1, title: ".env"}]
        })
        |> then(&VaultItemEvents.apply_link_project_scan(&1, {:ok, project_data}))

      {:noreply, result} = VaultItemEvents.confirm_link_project(%{}, scan_socket)

      assert result.assigns.link_project_error =~ "overwrite"
      assert result.assigns.show_link_project_modal
    end

    @tag :crdt_nif_required
    test "confirms without strategy when folder has no items" do
      dir = temp_project_dir!()
      folder = project_folder_fixture()
      password = "empty-folder-link-#{System.unique_integer([:positive])}"

      {:ok, project_data} = AutoDetect.scan_disk(dir)

      scan_socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: password,
          show_link_project_modal: true,
          notes: [],
          vault_items: [],
          link_project_existing_notes_strategy: nil
        })
        |> then(&VaultItemEvents.apply_link_project_scan(&1, {:ok, project_data}))

      {:noreply, confirm_socket} =
        VaultItemEvents.confirm_link_project(%{}, scan_socket)

      assert confirm_socket.assigns.show_link_project_modal == false
      assert confirm_socket.assigns.info =~ "Project Details"

      updated_folder = ProjectVault.get_project_folder!(folder.id)
      assert updated_folder.linked_project_path == dir
    end

    @tag :crdt_nif_required
    test "overwrite strategy updates existing vault item with same title" do
      dir = temp_project_dir!()
      folder = project_folder_fixture()
      password = "overwrite-link-#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               ProjectVault.save_vault_item(
                 %{
                   title: ".env",
                   kind: "env_note",
                   security_mode: "global_passkey",
                   project_folder_id: folder.id,
                   body: "OLD=1\n"
                 },
                 password
               )

      {:ok, project_data} = AutoDetect.scan_disk(dir)

      scan_socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: password,
          link_project_existing_notes_strategy: "overwrite"
        })
        |> then(&VaultItemEvents.apply_link_project_scan(&1, {:ok, project_data}))
        |> then(
          &%{
            &1
            | assigns: Map.put(&1.assigns, :link_project_existing_notes_strategy, "overwrite")
          }
        )

      {:noreply, _} = VaultItemEvents.confirm_link_project(%{}, scan_socket)

      items = ProjectVault.list_vault_items_by_folder(folder.id)
      env_items = Enum.filter(items, &(&1.title == ".env"))
      assert length(env_items) == 1
      assert {:ok, body} = ProjectVault.decrypt_vault_item_body(hd(env_items), password)
      assert body =~ "API_KEY=from-disk"
      refute body =~ "OLD=1"
    end
  end
end
