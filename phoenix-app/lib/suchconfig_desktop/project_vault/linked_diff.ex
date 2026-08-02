defmodule SuchConfigDesktop.ProjectVault.LinkedDiff do
  @moduledoc false

  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter

  @spec lines(String.t(), String.t()) :: [
          %{kind: :same | :add | :remove, text: String.t()}
        ]
  def lines(left, right) do
    left_lines = left |> LinkedFrontmatter.normalize_body() |> String.split("\n", trim: false)
    right_lines = right |> LinkedFrontmatter.normalize_body() |> String.split("\n", trim: false)

    diff_lines(left_lines, right_lines, [])
    |> Enum.reverse()
  end

  defp diff_lines([], right, acc) do
    Enum.reduce(right, acc, fn line, a -> [%{kind: :add, text: line} | a] end)
  end

  defp diff_lines(left, [], acc) do
    Enum.reduce(left, acc, fn line, a -> [%{kind: :remove, text: line} | a] end)
  end

  defp diff_lines([h | tl], [h | tr], acc) do
    diff_lines(tl, tr, [%{kind: :same, text: h} | acc])
  end

  defp diff_lines([lh | lt], [rh | rt], acc) do
    if lh == rh do
      diff_lines(lt, rt, [%{kind: :same, text: lh} | acc])
    else
      diff_lines(lt, [rh | rt], [%{kind: :remove, text: lh} | acc])
    end
  end
end
