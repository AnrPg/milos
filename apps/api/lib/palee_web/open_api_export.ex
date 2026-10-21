defmodule PaleeWeb.OpenApiExport do
  @moduledoc """
  Deterministic JSON rendering of the OpenAPI spec (ADR-134).

  Jason writes map keys in map iteration order. Maps with more than 32 keys
  (e.g. `components.schemas`, `paths`) iterate in hash order, so adding one
  schema or path reshuffles unrelated entries, and small maps with atom keys
  iterate in atom-table order, which depends on load order. Both turn every
  regeneration of `apps/web/src/api/generated/openapi.json` (and the
  `schema.ts` generated from it) into a noisy diff that conflicts across
  branches.

  `encode!/1` first encodes with the regular encoders (so OpenApiSpex's
  struct encoders still drop `nil` fields and add `$ref`s), then re-encodes
  with every object's keys sorted by byte order. Array order is kept, since
  it is meaningful (`required`, `enum`, `parameters`, `servers`, ...).
  """

  @doc "Pretty-printed JSON with recursively sorted object keys and a trailing newline."
  @spec encode!(term()) :: String.t()
  def encode!(value) do
    value
    |> Jason.encode!()
    |> Jason.decode!()
    |> sort_keys()
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  defp sort_keys(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> {key, sort_keys(value)} end)
    |> Jason.OrderedObject.new()
  end

  defp sort_keys(list) when is_list(list), do: Enum.map(list, &sort_keys/1)
  defp sort_keys(scalar), do: scalar
end
