defmodule SuchConfigDesktopWeb.Sc.TrustedFolderBadge do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Pill

  attr :display_path, :string, default: nil
  attr :synced, :boolean, default: false
  attr :watcher_running, :boolean, default: false
  attr :class, :string, default: nil
  attr :id, :string, default: nil

  def trusted_folder_badge(assigns) do
    ~H"""
    <span
      :if={is_binary(@display_path) and @display_path != ""}
      id={@id}
      class={@class}
    >
      <.pill tone={if(@synced, do: "ok", else: "warn")}>
        <.icon name="folder-open" size={12} />
        <span>
          Trusted Folder: {@display_path}{sync_suffix(@synced, @watcher_running)}
        </span>
      </.pill>
    </span>
    """
  end

  defp sync_suffix(true, true), do: " ✓ Backed up"
  defp sync_suffix(false, true), do: " · Watching"
  defp sync_suffix(_, false), do: " · Paused"
end
