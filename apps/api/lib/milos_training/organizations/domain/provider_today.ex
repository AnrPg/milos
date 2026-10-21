defmodule MilosTraining.Organizations.Domain.ProviderToday do
  @moduledoc """
  The «Σήμερα» card across providers (ADR-162; board 17, Q2): each
  provider's items for the day, computed in that provider's own context,
  merged in time order. Untimed items (a coach's programme of the day, the
  WOD) come first. One provider failing never hides the others: its id is
  listed in `failed` and the result is marked `partial`.
  """

  @doc """
  Merges `[{provider_id, {:ok, items} | {:error, reason}}]`. Each item is a
  map with `at` (a `DateTime`, or nil when untimed) and `kind`.
  """
  def merge(results) do
    {ok, failed} = Enum.split_with(results, fn {_id, result} -> match?({:ok, _}, result) end)

    items =
      ok
      |> Enum.flat_map(fn {_id, {:ok, items}} -> items end)
      |> Enum.sort_by(&sort_key/1)

    %{
      items: items,
      partial: failed != [],
      failed: Enum.map(failed, fn {id, _error} -> id end)
    }
  end

  defp sort_key(%{at: nil} = item), do: {0, 0, item.kind, Map.get(item, :title) || ""}

  defp sort_key(%{at: %DateTime{} = at} = item),
    do: {1, DateTime.to_unix(at, :microsecond), item.kind, Map.get(item, :title) || ""}
end
