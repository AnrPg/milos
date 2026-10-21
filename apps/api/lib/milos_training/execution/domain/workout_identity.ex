defmodule MilosTraining.Execution.Domain.WorkoutIdentity do
  @moduledoc """
  The canonical identity of a workout across providers (ADR-162; board 17,
  Q4: «Fran at the box and Fran with the coach are the same benchmark»).
  Every provider keeps its own library, so ids differ; the Vault and Πρόοδος
  group attempts by this key instead, first match wins:

  1. `benchmark:<slug>` — a `benchmark:<slug>` tag on the workout, or a title
     that normalises to a known benchmark name (Fran, Grace, Murph, …).
  2. `library:<id>` — the library workout it was copied from
     (`source_workout_id`), so copies of one workout stay together.
  3. `title:<normalised title>[:<type>]` — same name and discipline.

  Normalising lowercases, strips accents and punctuation and collapses
  spaces, so «Fran», "FRAN " and "fran!" match. An attempt with no workout
  and no title has no identity and is left out of the grouping.
  """

  @benchmarks ~w(
    amanda angie annie barbara chelsea cindy diane elizabeth eva fran grace
    gwen helen isabel jackie karen kelly linda lynne mary nancy nicole
    murph dt jt badger michael nate randy ryan josh daniel
    filthy_fifty fight_gone_bad
  )

  def benchmarks, do: @benchmarks

  @doc "Lowercase, accents and punctuation stripped, single spaces."
  def normalize(nil), do: ""

  def normalize(text) when is_binary(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  @doc "The benchmark slug of a workout, or nil."
  def benchmark_slug(title, tags \\ []) do
    Enum.find_value(List.wrap(tags), &tag_slug/1) || title_slug(title)
  end

  defp tag_slug("benchmark:" <> slug) do
    slug = slug |> normalize() |> String.replace(" ", "_")
    if slug != "", do: slug
  end

  defp tag_slug(_tag), do: nil

  defp title_slug(title) do
    slug = title |> normalize() |> String.replace(" ", "_")
    if slug in @benchmarks, do: slug
  end

  @doc """
  The identity key of one attempt: `%{title, type, tags, source_workout_id}`
  (any may be missing).
  """
  def key(attrs) when is_map(attrs) do
    title = Map.get(attrs, :title)
    type = Map.get(attrs, :type)

    cond do
      slug = benchmark_slug(title, Map.get(attrs, :tags, [])) ->
        "benchmark:" <> slug

      is_binary(Map.get(attrs, :source_workout_id)) ->
        "library:" <> attrs.source_workout_id

      normalize(title) != "" ->
        "title:" <> normalize(title) <> type_suffix(type)

      true ->
        nil
    end
  end

  defp type_suffix(nil), do: ""
  defp type_suffix(""), do: ""
  defp type_suffix(type), do: ":" <> to_string(type)

  @doc "The benchmark slug of a key, or nil."
  def key_benchmark("benchmark:" <> slug), do: slug
  def key_benchmark(_key), do: nil

  @doc "A display name for a benchmark slug: `filthy_fifty` → «Filthy Fifty»."
  def benchmark_name(slug) do
    slug
    |> String.split("_")
    |> Enum.map_join(" ", fn
      part when part in ~w(dt jt) -> String.upcase(part)
      part -> String.capitalize(part)
    end)
  end
end
