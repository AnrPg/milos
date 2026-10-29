defmodule Palee.Workouts.Domain.StructuredPlanPropertyTest do
  @moduledoc """
  ADR-270: the validator, the read model and the notation readers take any
  value without raising. Random JSON, random notation-like strings and the
  corpus sections with random parts swapped out (a small generator: the
  project has no StreamData). Seeded from the ExUnit seed, so a failure
  replays with `--seed`.
  """
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.{Notation, Prescription, Rounds}

  @corpus_path Path.expand("../../../support/fixtures/structured_plan_corpus.json", __DIR__)
  @external_resource @corpus_path
  @sections @corpus_path
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("sections")
            |> Enum.map(& &1["section"])

  @runs 400

  @fragments ~w(0 1 3 4 10 12 22,5 60 999 1000 1e9 99999999999 -1 +5 -0:05 : :30 1:00 2:00
    x × χ X * - – — − , / . … ... → -> => ως έως ή or % kg κιλά lb lbs kgs m km μ cal kcal
    θερμίδες s sec ″ " ' ′ min λεπτά max MAX amrap μέγιστο in σε each side /side ανά πλευρά
    BW bodyweight RPE @8 rpe z2 zone ζώνη /500m /km 31X1 3Χ1 20X0 up ↑ sets σετ e/s
    for_time amrap emom intervals sets rest pyramid cluster drop superset)

  setup do
    :rand.seed(:exsss, {ExUnit.configuration()[:seed] || 0, 270, 2026})
    :ok
  end

  test "the validator and the read model take any value" do
    for _ <- 1..@runs do
      value = json(4)
      assert_total(value)
    end
  end

  test "corpus sections with random parts swapped out" do
    for _ <- 1..@runs do
      section = @sections |> Enum.random() |> mutate(1 + :rand.uniform(4))
      assert_total(section)
    end
  end

  test "the notation readers take any string or value" do
    for _ <- 1..(@runs * 5) do
      text = if :rand.uniform(10) == 1, do: json(2), else: notation()

      row = %{
        "cells" =>
          Enum.map(1..:rand.uniform(4), fn _ -> %{"l" => notation(), "pace" => notation()} end)
      }

      _ = Notation.parse_dose(text)
      _ = Notation.parse_load(text)
      _ = Notation.parse_clock(text, Enum.random([:min, :smart]))
      _ = Notation.parse_times(text, Enum.random([:min, :smart]))
      _ = Notation.parse_count_range(text)
      _ = Notation.tempo_canonical(text)
      _ = Notation.show_dose_at(Notation.parse_dose(text), :rand.uniform(5))
      _ = Notation.set_loads(row, :rand.uniform(12))
      _ = Notation.set_load_readings(row, :rand.uniform(12))
      _ = Notation.progress(row, "pace", :rand.uniform(12), true)
      _ = Notation.measure_cell_errors(row, "pace", :rand.uniform(12), true)
    end
  end

  defp assert_total(value) do
    issues = StructuredPlan.errors(value)
    assert is_list(issues)
    assert Enum.all?(issues, &(is_binary(&1.path) and is_binary(&1.code)))

    _ = value |> Prescription.build() |> Prescription.to_json()

    # The web runs the readers on sections without these two codes only.
    if is_map(value) and not Enum.any?(issues, &(&1.code in ["bad_shape", "unknown_flow"])) do
      _ = {Rounds.describe(value), Rounds.timeline(value), Rounds.summary(value)}

      value["blocks"]
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.each(fn {_block, b} ->
        {Rounds.occurrences(value, b), Rounds.block_label(value, b)}
      end)
    end
  end

  # ── generators ───────────────────────────────────────

  defp notation do
    1..:rand.uniform(4)
    |> Enum.map(fn _ -> Enum.random(@fragments) end)
    |> Enum.join(Enum.random(["", " ", "  "]))
  end

  defp json(0), do: leaf()

  defp json(depth) do
    case :rand.uniform(6) do
      1 -> Enum.map(1..:rand.uniform(4), fn _ -> json(depth - 1) end)
      2 -> Map.new(1..:rand.uniform(4), fn _ -> {key(), json(depth - 1)} end)
      _leaf -> leaf()
    end
  end

  defp leaf do
    Enum.random([
      nil,
      true,
      false,
      :rand.uniform(2000) - 1000,
      :rand.uniform() * 1.0e10,
      "",
      notation(),
      notation()
    ])
  end

  defp key do
    Enum.random(
      ~w(v flow params blocks interrupt mods structs preset score id kind name dose load
      cells d l x extra group exerciseRef note sets rest cap dur every times work off rounds intEvery
      tempo pace rpe zone side interrupt hr hrTarget perRound kind clusters intra drops dropby minis)
    )
  end

  # Swaps a random node (at any depth) for a random value, `n` times.
  defp mutate(value, 0), do: value
  defp mutate(value, n), do: value |> swap() |> mutate(n - 1)

  defp swap(%{} = map) when map_size(map) > 0 do
    case :rand.uniform(4) do
      1 -> json(2)
      2 -> Map.put(map, key(), json(2))
      _deeper -> Map.update!(map, map |> Map.keys() |> Enum.random(), &swap/1)
    end
  end

  defp swap([_ | _] = list) do
    case :rand.uniform(4) do
      1 -> json(2)
      2 -> List.insert_at(list, :rand.uniform(length(list) + 1) - 1, json(2))
      _deeper -> List.update_at(list, :rand.uniform(length(list)) - 1, &swap/1)
    end
  end

  defp swap(_leaf), do: json(2)
end
