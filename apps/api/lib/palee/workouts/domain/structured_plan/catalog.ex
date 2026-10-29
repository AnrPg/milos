defmodule Palee.Workouts.Domain.StructuredPlan.Catalog do
  @moduledoc """
  What a structured WOD section can be made of (ADR-270), pure: the server
  copy of the web catalog (`apps/web/src/lib/structured-plan/catalog.ts`).

  Three levels that never mix: flows (how the clock runs, with their params,
  score keys, allowed structures and add-ons), structures (one set or round
  of an exercise or group) and add-ons (mods). Presets only matter here for
  the score they add to their flow. Change both copies together.
  """

  @typedoc "A param's kind and how a bare number reads for time fields."
  @type param_def :: %{
          key: String.t(),
          kind: :time | :times | :count | :range | :text,
          bare: :min | :smart
        }

  @flows %{
    "sets" => %{
      layout: :grid,
      params: [{"sets", :range, :smart}, {"rest", :time, :smart}],
      scores: ~w(none best_load reps),
      structs: ~w(single superset complex cluster drop restpause),
      mods: ~w(interrupt)
    },
    "for_time" => %{
      layout: :loop,
      params: [{"rounds", :count, :smart}, {"cap", :time, :min}],
      scores: ~w(time rounds_reps),
      structs: ~w(single superset complex),
      mods: ~w(interrupt)
    },
    "amrap" => %{
      layout: :loop,
      params: [{"dur", :times, :min}, {"rest", :time, :smart}],
      scores: ~w(rounds_reps reps),
      structs: ~w(single superset complex),
      mods: ~w(interrupt)
    },
    "emom" => %{
      layout: :slots,
      params: [{"every", :time, :smart}, {"times", :count, :smart}],
      scores: ~w(none done reps),
      structs: ~w(single superset complex cluster),
      mods: []
    },
    "intervals" => %{
      layout: :strip,
      params: [{"work", :time, :smart}, {"off", :time, :smart}, {"rounds", :count, :smart}],
      scores: ~w(total_reps lowest_round distance),
      structs: ~w(single superset complex),
      mods: ~w(hr)
    },
    "rest" => %{
      layout: :none,
      params: [{"dur", :time, :smart}],
      scores: ~w(none),
      structs: [],
      mods: []
    }
  }

  @mods %{
    "interrupt" => [{"intEvery", :time, :smart}],
    "hr" => [{"hrTarget", :count, :smart}]
  }

  @structs %{
    "single" => %{group: false, params: []},
    "cluster" => %{group: false, params: [{"clusters", :count}, {"intra", :time}]},
    "drop" => %{group: false, params: [{"drops", :count}, {"dropby", :text}]},
    "restpause" => %{group: false, params: [{"minis", :count}, {"intra", :time}]},
    "superset" => %{group: true, params: []},
    "complex" => %{group: true, params: []}
  }

  # Measures a row can add; `side` is a flag with no value, `tempo` is text.
  @measures %{
    "pace" => %{clock: true, max: nil, flag: false, text: false},
    "tempo" => %{clock: false, max: nil, flag: false, text: true},
    "rpe" => %{clock: false, max: 10, flag: false, text: false},
    "rir" => %{clock: false, max: nil, flag: false, text: false},
    "zone" => %{clock: false, max: nil, flag: false, text: false},
    "height" => %{clock: false, max: nil, flag: false, text: false},
    "dist" => %{clock: false, max: nil, flag: false, text: false},
    "hold" => %{clock: true, max: nil, flag: false, text: false},
    "side" => %{clock: false, max: nil, flag: true, text: false}
  }

  # The score a preset adds to its flow's list.
  @preset_scores %{"billat" => "distance", "death_by" => "rounds_reps", "edt" => "reps"}

  def flow_keys, do: ~w(sets for_time amrap emom intervals rest)
  def flow?(flow), do: Map.has_key?(@flows, flow)
  def flow(flow), do: Map.fetch!(@flows, flow)
  def layout(flow), do: flow(flow).layout
  def mod_keys, do: @mods |> Map.keys() |> Enum.sort()
  def struct_keys, do: ~w(single cluster drop restpause superset complex)
  def struct(kind), do: Map.get(@structs, kind)
  def measure_keys, do: ~w(pace tempo rpe rir zone height dist hold side)
  def measure(key), do: Map.get(@measures, key)

  def score_keys,
    do: ~w(none best_load reps time rounds_reps done total_reps lowest_round distance)

  @doc "The params a flow reads with the add-ons switched on (`mods`)."
  @spec param_defs(String.t(), map() | nil, (term() -> boolean())) :: [param_def()]
  def param_defs(flow, mods, on? \\ &(&1 == true)) do
    spec = flow(flow)

    extra =
      spec.mods
      |> Enum.filter(&(is_map(mods) and on?.(Map.get(mods, &1))))
      |> Enum.flat_map(&Map.fetch!(@mods, &1))

    Enum.map(spec.params ++ extra, fn {key, kind, bare} -> %{key: key, kind: kind, bare: bare} end)
  end

  @doc "Every param key a flow may hold (its own and all its add-ons'), on or off."
  @spec allowed_params(String.t()) :: [String.t()]
  def allowed_params(flow) do
    spec = flow(flow)
    Enum.map(spec.params ++ Enum.flat_map(spec.mods, &Map.fetch!(@mods, &1)), &elem(&1, 0))
  end

  @doc "The scores of a section: its flow's, plus its preset's own."
  @spec scores(String.t(), String.t() | nil) :: [String.t()]
  def scores(flow, preset) do
    base = flow(flow).scores

    case Map.get(@preset_scores, preset) do
      nil -> base
      extra -> if extra in base, do: base, else: base ++ [extra]
    end
  end

  @doc "The flow writes values per column for this row (the sets grid, or per round on)."
  @spec uses_cells?(String.t(), map()) :: boolean()
  def uses_cells?(flow, row),
    do: layout(flow) == :grid or Map.get(row, "perRound") not in [nil, false, 0, ""]
end
