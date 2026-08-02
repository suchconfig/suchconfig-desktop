defmodule Mix.Tasks.SuchconfigDesktop.ListLegacyNotes do
  @shortdoc "Lists encrypted notes that will be removed by the legacy-notes cleanup migration"
  @moduledoc """
  Runs a dry-run of the legacy notes cleanup: counts and lists notes that have
  encrypted content (encryption_version = 1, raw_content_encrypted set). These
  are the notes that the migration 20260203020000_add_security_mode_remove_legacy_notes
  will delete (treated as per-note password / legacy).

  Run before migrating to preview: `mix suchconfig_desktop.list_legacy_notes`
  """

  use Mix.Task
  import Ecto.Query
  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.EnvManager.Note

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    legacy =
      from(n in Note,
        where: n.encryption_version == 1 and not is_nil(n.raw_content_encrypted),
        select: %{id: n.id, title: n.title, project_folder_id: n.project_folder_id},
        order_by: [n.project_folder_id, n.title]
      )
      |> Repo.all()

    count = length(legacy)
    IO.puts("Notes that will be removed by the legacy cleanup migration: #{count}")

    if count > 0 do
      IO.puts("")

      Enum.each(legacy, fn %{id: id, title: title, project_folder_id: folder_id} ->
        IO.puts("  [#{id}] folder_id=#{folder_id}  #{title}")
      end)
    end
  end
end
