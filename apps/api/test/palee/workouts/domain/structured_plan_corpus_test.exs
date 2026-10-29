defmodule Palee.Workouts.Domain.StructuredPlanCorpusTest do
  @moduledoc """
  ADR-270 parity: every section of the shared corpus
  (`test/support/fixtures/structured_plan_corpus.json`, byte-identical to the
  web's `__fixtures__/corpus.json`) gets the same issues and the same
  readings here as in the web `corpus.test.ts`.
  """
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.{Catalog, Notation, Prescription, Rounds}

  @corpus_path Path.expand("../../../support/fixtures/structured_plan_corpus.json", __DIR__)
  @external_resource @corpus_path
  @sections @corpus_path |> File.read!() |> Jason.decode!() |> Map.fetch!("sections")

  defp entry(id), do: Enum.find(@sections, &(&1["id"] == id))

  test "the corpus has at least 60 sections with unique ids" do
    assert length(@sections) >= 60
    assert @sections |> Enum.map(& &1["id"]) |> Enum.uniq() |> length() == length(@sections)
  end

  for %{"id" => id} <- @sections do
    test "corpus #{id}" do
      run(entry(unquote(id)))
    end
  end

  defp run(%{"section" => section, "expect" => expect}) do
    assert sort_issues(StructuredPlan.errors(section)) ==
             sort_issues(Enum.map(expect["issues"], &%{path: &1["path"], code: &1["code"]}))

    if not Enum.any?(expect["issues"], &(&1["code"] in ["bad_shape", "unknown_flow"])) do
      _ = {Rounds.describe(section), Rounds.timeline(section), Rounds.summary(section)}

      section["blocks"]
      |> Enum.with_index()
      |> Enum.each(fn {_block, b} ->
        {Rounds.occurrences(section, b), Rounds.block_label(section, b)}
      end)
    end

    # The read model takes any section without raising.
    _ = section |> Prescription.build() |> Prescription.to_json()

    Enum.each(expect["checks"], &check(section, &1))
  end

  defp sort_issues(issues), do: issues |> Enum.map(&"#{&1.path}:#{&1.code}") |> Enum.sort()

  # ── checks (as in corpus.test.ts) ──────────────────────

  defp check(s, %{"type" => "dose"} = c) do
    dose = Notation.parse_dose(at(s, c["path"]))
    refute dose == :bad, "#{c["path"]} does not read"
    assert_match(js(dose), c["expect"], c)
    if c["noAmbiguity"], do: refute(Map.has_key?(dose, :ambiguous), inspect(dose))
  end

  defp check(s, %{"type" => "doseAt"} = c),
    do:
      assert(Notation.show_dose_at(Notation.parse_dose(at(s, c["path"])), c["i"]) == c["expect"])

  defp check(s, %{"type" => "load"} = c),
    do: assert_match(js(Notation.parse_load(at(s, c["path"]))), c["expect"], c)

  defp check(s, %{"type" => "setLoads"} = c),
    do: assert(js(Notation.set_loads(at(s, c["path"]), c["n"])) == c["expect"])

  defp check(s, %{"type" => "progress"} = c),
    do:
      assert(
        Notation.progress(at(s, c["path"]), c["key"], c["n"], c["clock"] == true) == c["expect"]
      )

  defp check(s, %{"type" => "repeat"} = c),
    do: assert(Notation.repeat_text(at(s, c["path"]), c["key"], c["n"]) == c["expect"])

  defp check(s, %{"type" => "tempo"} = c),
    do: assert(Notation.tempo_canonical(at(s, c["path"])) == c["expect"])

  defp check(s, %{"type" => "param", "key" => key} = c) do
    defs = Catalog.param_defs(s["flow"], %{}) ++ [%{key: "intEvery", kind: :time, bare: :smart}]
    def = Enum.find(defs, &(&1.key == key))
    assert_match(js(StructuredPlan.read_param(def, s["params"][key])), c["expect"], c)
  end

  defp check(s, %{"type" => "rounds", "expect" => expect}) do
    expected = if expect == "Infinity", do: :infinity, else: expect
    assert Rounds.total_rounds(s) == expected
  end

  defp check(s, %{"type" => "occurrences"} = c),
    do: assert(js(Rounds.occurrences(s, c["block"])) == c["expect"])

  defp check(s, %{"type" => "blockLabel"} = c),
    do: assert_match(js(Rounds.block_label(s, c["block"])), c["expect"], c)

  defp check(s, %{"type" => "units"} = c) do
    units = StructuredPlan.units(list_of(s, c["block"]))
    assert Enum.map(units, &length(&1.rows)) == c["expect"]
  end

  defp check(s, %{"type" => "struct"} = c) do
    unit = s |> list_of(c["block"]) |> StructuredPlan.units() |> Enum.at(c["unit"])
    assert StructuredPlan.struct_of(s, unit) == c["expect"]
  end

  defp check(s, %{"type" => "timeline", "expect" => expect}) do
    t = Rounds.timeline(s)

    assert %{
             "open" => t.open,
             "total" => t.total,
             "segments" => length(t.segments),
             "interrupts" => t.interrupts
           } == expect
  end

  defp check(s, %{"type" => "describe", "expect" => expect}),
    do: assert(Enum.map(Rounds.describe(s), & &1.key) == expect)

  defp check(s, %{"type" => "summary"} = c),
    do: assert_match(js(Rounds.summary(s)), c["expect"], c)

  # ── helpers ──────────────────────────────────────────

  defp at(root, path) do
    path
    |> String.split(".")
    |> Enum.reduce(root, fn
      key, %{} = node -> Map.get(node, key)
      key, node when is_list(node) -> Enum.at(node, String.to_integer(key))
      _key, _node -> nil
    end)
  end

  defp list_of(s, -1), do: s["interrupt"] || []
  defp list_of(s, b), do: Enum.at(s["blocks"], b)

  # Elixir readings in the web's JSON form: camelCase keys, atoms as strings.
  defp js(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {key, value} -> {camel(key), js(value)} end)

  defp js(list) when is_list(list), do: Enum.map(list, &js/1)
  defp js(nil), do: nil
  defp js(value) when is_boolean(value), do: value
  defp js(value) when is_atom(value), do: value |> Atom.to_string() |> camelize()
  defp js(value), do: value

  defp camel(key) when is_atom(key), do: key |> Atom.to_string() |> camelize()
  defp camel(key), do: key

  defp camelize(text) do
    [head | rest] = String.split(text, "_")
    head <> Enum.map_join(rest, &String.capitalize/1)
  end

  # Jest `toMatchObject`: objects match on the expected keys, arrays element-wise.
  defp assert_match(actual, expected, check) do
    assert matches?(actual, expected),
           "#{inspect(check)}\nactual: #{inspect(actual)}"
  end

  defp matches?(%{} = actual, %{} = expected),
    do:
      Enum.all?(expected, fn {key, value} ->
        Map.has_key?(actual, key) and matches?(actual[key], value)
      end)

  defp matches?(actual, expected) when is_list(actual) and is_list(expected),
    do:
      length(actual) == length(expected) and
        Enum.all?(Enum.zip(actual, expected), fn {a, e} -> matches?(a, e) end)

  defp matches?(actual, expected) when is_number(actual) and is_number(expected),
    do: actual == expected

  defp matches?(actual, expected), do: actual === expected
end
