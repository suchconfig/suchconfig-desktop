defmodule SuchConfigCore.Importers.ImportData do
  @moduledoc """
  Normalized vault import payload shared by password-manager parsers.
  """

  @type folder :: %{
          external_id: String.t() | nil,
          name: String.t()
        }

  @type item :: %{
          external_id: String.t() | nil,
          folder_name: String.t() | nil,
          kind: String.t(),
          title: String.t(),
          body: String.t(),
          frontmatter: %{optional(String.t()) => String.t()},
          skipped?: boolean(),
          skip_reason: String.t() | nil
        }

  @type t :: %__MODULE__{
          source: atom(),
          folders: [folder()],
          items: [item()],
          warnings: [String.t()]
        }

  @enforce_keys [:source]
  defstruct source: nil, folders: [], items: [], warnings: []

  @doc """
  Builds an empty import payload for the given source atom.
  """
  @spec new(atom()) :: t()
  def new(source) when is_atom(source) do
    %__MODULE__{source: source, folders: [], items: [], warnings: []}
  end
end
