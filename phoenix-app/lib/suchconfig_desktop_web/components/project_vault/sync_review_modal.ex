defmodule SuchConfigDesktopWeb.Components.ProjectVault.SyncReviewModal do
  use Phoenix.Component

  import SuchConfigDesktopWeb.CoreComponents, only: [icon: 1]

  attr :show, :boolean, default: false
  attr :diff_lines, :list, default: []
  attr :relative_path, :string, default: nil

  def sync_review_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      id="sync-review-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <div class="absolute inset-0 bg-black/50" phx-click="sync_review_reject"></div>
      <div class="relative w-full max-w-4xl max-h-[90vh] overflow-y-auto rounded-xl border border-gray-200 bg-white shadow-xl dark:border-slate-600 dark:bg-slate-900">
        <div class="flex items-start justify-between gap-3 border-b border-gray-200 px-5 py-4 dark:border-slate-700">
          <div>
            <h3 class="text-lg font-semibold text-gray-900 dark:text-slate-100">
              Review linked file changes
            </h3>
            <p :if={@relative_path} class="mt-1 font-mono text-xs text-gray-500 dark:text-slate-400">
              {@relative_path}
            </p>
            <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
              Compare vault content with the file on disk. Accept applies disk content to your vault item.
            </p>
          </div>
          <button
            type="button"
            phx-click="sync_review_reject"
            class="rounded p-1 text-gray-500 hover:bg-gray-100 dark:hover:bg-slate-800"
            aria-label="Close"
          >
            <.icon name="lucide-x" class="h-5 w-5" />
          </button>
        </div>
        <div class="space-y-3 px-5 py-4">
          <div class="max-h-[50vh] overflow-auto rounded border border-gray-200 bg-gray-50 p-3 font-mono text-xs dark:border-slate-700 dark:bg-slate-950">
            <div
              :for={{line, idx} <- Enum.with_index(@diff_lines)}
              id={"sync-diff-line-#{idx}"}
              class={diff_line_class(line.kind)}
            >
              {diff_prefix(line.kind)}{line.text}
            </div>
          </div>
          <div class="flex justify-end gap-2 border-t border-gray-200 pt-4 dark:border-slate-700">
            <button
              type="button"
              phx-click="sync_review_reject"
              class="rounded-lg border border-gray-300 px-4 py-2 text-sm text-gray-700 dark:border-slate-600 dark:text-slate-300"
            >
              Reject
            </button>
            <button
              type="button"
              id="sync-review-accept-button"
              phx-click="sync_review_accept"
              class="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
            >
              Accept
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp diff_line_class(:add), do: "text-emerald-700 dark:text-emerald-300"
  defp diff_line_class(:remove), do: "text-red-700 dark:text-red-300 line-through"
  defp diff_line_class(_), do: "text-gray-700 dark:text-slate-300"

  defp diff_prefix(:add), do: "+ "
  defp diff_prefix(:remove), do: "- "
  defp diff_prefix(_), do: "  "
end
