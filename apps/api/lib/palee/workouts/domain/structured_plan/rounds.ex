defmodule Palee.Workouts.Domain.StructuredPlan.Rounds do
  @moduledoc """
  Rounds, blocks, the clock and the words of a structured plan section
  (ADR-270), pure: a port of the web `rounds.ts` and `describe.ts`.

  Blocks are kinds of round that alternate: with two blocks, block 0 is done
  in rounds 1, 3, 5… and block 1 in rounds 2, 4, 6…. AMRAP, and an EMOM
  without `times` (Death by), have no last round (`:infinity`).

  `describe/1`, `summary/1` and `block_label/2` return i18n keys under
  `PlanCore.*` with their values, exactly as the web does, for any surface
  that words a plan.
  """

  alias Palee.Workouts.Domain.StructuredPlan.{Catalog, Notation}

  @max_columns 12
  # Length shown for an uncapped For Time with interruptions (display only).
  @uncapped_display_secs 12 * 60

  def max_columns, do: @max_columns

  defp params(section) do
    case Map.get(section, "params") do
      %{} = params -> params
      _other -> %{}
    end
  end

  defp blocks(section) do
    case Map.get(section, "blocks") do
      blocks when is_list(blocks) -> blocks
      _other -> []
    end
  end

  defp mod?(section, key), do: match?(%{^key => true}, Map.get(section, "mods"))

  @doc "A parameter as seconds (cap and dur read bare numbers as minutes), or nil."
  @spec param_secs(map(), String.t()) :: number() | nil
  def param_secs(section, key) do
    case Map.get(params(section), key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          nil
        else
          case Notation.parse_clock(value, if(key in ["cap", "dur"], do: :min, else: :smart)) do
            secs when is_number(secs) and secs > 0 -> secs
            _other -> nil
          end
        end

      _other ->
        nil
    end
  end

  @doc "A parameter as a positive whole number, or nil."
  @spec param_count(map(), String.t()) :: pos_integer() | nil
  def param_count(section, key), do: Notation.parse_count(Map.get(params(section), key))

  @doc "Sets of a `sets` flow (\"4\", \"3-4\"); unreadable is 1–1."
  @spec sets_range(map()) :: %{min: pos_integer(), max: pos_integer()}
  def sets_range(section),
    do: Notation.parse_count_range(Map.get(params(section), "sets")) || %{min: 1, max: 1}

  @doc "How many rounds the section runs; `:infinity` for AMRAP and an EMOM without times."
  @spec total_rounds(map()) :: pos_integer() | :infinity
  def total_rounds(section) do
    case Map.get(section, "flow") do
      "sets" -> sets_range(section).max
      "emom" -> param_count(section, "times") || :infinity
      "amrap" -> :infinity
      _other -> param_count(section, "rounds") || 1
    end
  end

  defp written_columns(section, list) do
    grid = Catalog.flow?(Map.get(section, "flow")) and Catalog.layout(section["flow"]) == :grid

    list
    |> Enum.filter(&is_map/1)
    |> Enum.filter(&(grid or Map.get(&1, "perRound") not in [nil, false]))
    |> Enum.flat_map(fn row ->
      case Map.get(row, "cells") do
        cells when is_list(cells) ->
          cells
          |> Enum.with_index(1)
          |> Enum.filter(fn {cell, _i} -> written?(cell) end)
          |> Enum.map(&elem(&1, 1))

        _other ->
          []
      end
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp written?(%{} = cell),
    do: Enum.any?(cell, fn {_key, value} -> value |> js_text() |> String.trim() != "" end)

  defp written?(_cell), do: false

  defp js_text(nil), do: ""
  defp js_text(value) when is_binary(value), do: value
  defp js_text(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp js_text(_value), do: "[object]"

  @doc """
  The rounds (1-based) block `b` is done in, at most #{@max_columns}. Open
  sections list the written rounds plus one empty column (at least 2).
  """
  @spec occurrences(map(), integer()) :: %{list: [pos_integer()], open: boolean()}
  def occurrences(section, b) do
    k = max(1, length(blocks(section)))
    total = total_rounds(section)
    open = total == :infinity

    want =
      if open,
        do: max(2, written_columns(section, List.wrap(Enum.at(blocks(section), b))) + 1),
        else: :infinity

    list =
      b
      |> Stream.iterate(&(&1 + k))
      |> Stream.with_index()
      |> Enum.reduce_while([], fn {i, count}, acc ->
        more = if open, do: count < want, else: i < total

        if more and count < @max_columns, do: {:cont, [i + 1 | acc]}, else: {:halt, acc}
      end)
      |> Enum.reverse()

    %{list: list, open: open}
  end

  @doc "The word for one column: set (sets), interval (EMOM, intervals) or round."
  @spec round_word(map()) :: String.t()
  def round_word(%{"flow" => "sets"}), do: "set"
  def round_word(%{"flow" => flow}) when flow in ["emom", "intervals"], do: "interval"
  def round_word(_section), do: "round"

  defp list_text(nums, more), do: Enum.join(nums, ", ") <> if(more, do: ", …", else: "")

  @doc "The label of a block, as `PlanCore.block.*` and its values."
  @spec block_label(map(), integer()) :: map()
  def block_label(section, b) do
    %{list: list, open: open} = occurrences(section, b)
    word = round_word(section)
    k = length(blocks(section))
    total = total_rounds(section)
    every = if section["flow"] == "emom", do: param_secs(section, "every")

    cond do
      total != :infinity and k >= total and length(list) == 1 ->
        %{key: "PlanCore.block.one", values: %{word: word, n: hd(list)}}

      every == 60 ->
        %{
          key: "PlanCore.block.minute",
          values: %{list: list_text(Enum.take(list, 3), length(list) > 3 or open)}
        }

      every ->
        two = Enum.take(list, 2)

        %{
          key: "PlanCore.block.slot",
          values: %{
            word: word,
            list: list_text(two, true),
            at: list_text(Enum.map(two, &Notation.mmss(every * (&1 - 1))), true)
          }
        }

      true ->
        %{
          key: "PlanCore.block.list",
          values: %{word: word, list: list_text(Enum.take(list, 3), open or length(list) > 3)}
        }
    end
  end

  @doc """
  The shape of the clock: `%{segments: [%{secs, kind, slot}], interrupts: [secs],
  total: secs | nil, open: boolean}` (EMOM slots, AMRAP windows with rest,
  intervals work / rest, For Time with interruptions as its cap).
  """
  @spec timeline(map()) :: map()
  def timeline(section) do
    k = max(1, length(blocks(section)))
    p = params(section)

    segments =
      case section["flow"] do
        "emom" ->
          emom_segments(section, k)

        "amrap" ->
          amrap_segments(p)

        "intervals" ->
          interval_segments(section, k)

        "for_time" ->
          if mod?(section, "interrupt"),
            do: [%{secs: param_secs(section, "cap") || @uncapped_display_secs, kind: "work"}],
            else: []

        _other ->
          []
      end

    case segments do
      {:open, segs} ->
        %{segments: segs, interrupts: [], total: nil, open: true}

      segs ->
        total = segs |> Enum.map(& &1.secs) |> Enum.sum()
        every = if mod?(section, "interrupt"), do: param_secs(section, "intEvery")

        interrupts =
          if every && total > 0,
            do: every |> Stream.iterate(&(&1 + every)) |> Enum.take_while(&(&1 < total)),
            else: []

        %{segments: segs, interrupts: interrupts, total: total, open: false}
    end
  end

  defp emom_segments(section, k) do
    e = param_secs(section, "every")
    n = param_count(section, "times")

    cond do
      is_nil(e) -> []
      n -> Enum.map(0..(n - 1), &%{secs: e, kind: "slot", slot: rem(&1, k)})
      true -> {:open, Enum.map(0..(k - 1), &%{secs: e, kind: "slot", slot: rem(&1, k)})}
    end
  end

  defp amrap_segments(p) do
    rest = if p["rest"] not in [nil, ""], do: Notation.parse_clock(p["rest"], :smart)

    case Notation.parse_times(p["dur"] || "", :min) do
      %{secs: secs} ->
        secs
        |> Enum.with_index()
        |> Enum.flat_map(fn {x, i} ->
          gap =
            if i > 0 and is_number(rest) and rest > 0, do: [%{secs: rest, kind: "rest"}], else: []

          gap ++ [%{secs: x, kind: "work"}]
        end)

      _other ->
        []
    end
  end

  defp interval_segments(section, k) do
    a = param_secs(section, "work")
    b = param_secs(section, "off") || if(mod?(section, "hr"), do: 60, else: 0)
    n = param_count(section, "rounds")

    if a && n do
      Enum.flat_map(0..(n - 1), fn i ->
        [%{secs: a, kind: "slot", slot: rem(i, k)}] ++
          if(b > 0, do: [%{secs: b, kind: "rest"}], else: [])
      end)
    else
      []
    end
  end

  @doc "The section as a sentence of parts (`PlanCore.describe.*`)."
  @spec describe(map()) :: [map()]
  def describe(section) do
    p = params(section)

    main =
      case section["flow"] do
        "emom" ->
          describe_emom(section)

        "amrap" ->
          describe_amrap(p)

        "for_time" ->
          describe_for_time(section, p)

        "intervals" ->
          [describe_intervals(section, p)]

        "sets" ->
          [describe_sets(p)]

        "rest" ->
          if truthy(p["dur"]),
            do: [%{key: "PlanCore.describe.rest", values: %{dur: p["dur"]}}],
            else: []

        _other ->
          []
      end

    main ++
      if mod?(section, "interrupt"),
        do: [%{key: "PlanCore.describe.interrupt", values: %{every: or_q(p["intEvery"])}}],
        else: []
  end

  defp describe_emom(section) do
    e = param_secs(section, "every")
    n = param_count(section, "times")

    cond do
      is_nil(e) ->
        []

      n ->
        [
          %{
            key: "PlanCore.describe.emom",
            values: %{every: Notation.clock(e), times: n, total: Notation.clock(e * n)}
          }
        ]

      true ->
        [%{key: "PlanCore.describe.emomOpen", values: %{every: Notation.clock(e)}}]
    end
  end

  defp describe_amrap(p) do
    case Notation.parse_times(p["dur"] || "", :min) do
      %{secs: [one]} ->
        [%{key: "PlanCore.describe.amrap", values: %{dur: Notation.clock(one)}}]

      %{secs: secs} ->
        values = %{count: length(secs), list: Enum.map_join(secs, ", ", &Notation.clock/1)}

        if truthy(p["rest"]),
          do: [
            %{
              key: "PlanCore.describe.amrapWindowsRest",
              values: Map.put(values, :rest, p["rest"])
            }
          ],
          else: [%{key: "PlanCore.describe.amrapWindows", values: values}]

      _other ->
        []
    end
  end

  defp describe_for_time(section, p) do
    rounds = param_count(section, "rounds") || 1

    if truthy(p["cap"]),
      do: [%{key: "PlanCore.describe.forTimeCap", values: %{rounds: rounds, cap: p["cap"]}}],
      else: [%{key: "PlanCore.describe.forTime", values: %{rounds: rounds}}]
  end

  defp describe_intervals(section, p) do
    if mod?(section, "hr"),
      do: %{
        key: "PlanCore.describe.intervalsHr",
        values: %{rounds: or_q(p["rounds"]), work: or_q(p["work"]), hr: or_q(p["hrTarget"])}
      },
      else: %{
        key: "PlanCore.describe.intervals",
        values: %{rounds: or_q(p["rounds"]), work: or_q(p["work"]), off: or_q(p["off"])}
      }
  end

  defp describe_sets(p) do
    if truthy(p["rest"]),
      do: %{key: "PlanCore.describe.setsRest", values: %{sets: or_q(p["sets"]), rest: p["rest"]}},
      else: %{key: "PlanCore.describe.sets", values: %{sets: or_q(p["sets"])}}
  end

  @doc "A closed section in one line: `params` parts and exercise names per block."
  @spec summary(map()) :: %{params: [map()], names: [[map()]]}
  def summary(section) do
    p = params(section)

    main =
      case section["flow"] do
        "emom" ->
          if truthy(p["times"]),
            do: [
              %{
                key: "PlanCore.summary.emom",
                values: %{every: or_q(p["every"]), times: p["times"]}
              }
            ],
            else: [%{key: "PlanCore.summary.emomOpen", values: %{every: or_q(p["every"])}}]

        "sets" ->
          [%{key: "PlanCore.summary.sets", values: %{sets: or_q(p["sets"])}}]

        "amrap" ->
          case Notation.parse_times(p["dur"] || "", :min) do
            %{secs: [one]} ->
              [%{key: "PlanCore.summary.dur", values: %{dur: Notation.clock(one)}}]

            %{secs: secs} ->
              [%{key: "PlanCore.summary.windows", values: %{count: length(secs)}}]

            _other ->
              []
          end

        "for_time" ->
          n = param_count(section, "rounds")
          if n && n > 1, do: [%{key: "PlanCore.summary.rounds", values: %{rounds: n}}], else: []

        "intervals" ->
          if mod?(section, "hr") and not truthy(p["off"]),
            do: [
              %{
                key: "PlanCore.summary.intervalsHr",
                values: %{rounds: or_q(p["rounds"]), work: or_q(p["work"])}
              }
            ],
            else: [
              %{
                key: "PlanCore.summary.intervals",
                values: %{rounds: or_q(p["rounds"]), work: or_q(p["work"]), off: or_q(p["off"])}
              }
            ]

        "rest" ->
          if truthy(p["dur"]),
            do: [%{key: "PlanCore.summary.dur", values: %{dur: p["dur"]}}],
            else: []

        _other ->
          []
      end

    params =
      main ++
        if mod?(section, "interrupt"),
          do: [%{key: "PlanCore.summary.interrupt", values: %{every: or_q(p["intEvery"])}}],
          else: []

    names =
      section
      |> blocks()
      |> Enum.map(fn block ->
        block
        |> List.wrap()
        |> Enum.filter(
          &(is_map(&1) and &1["kind"] == "ex" and is_binary(&1["name"]) and
              String.trim(&1["name"]) != "")
        )
        |> Enum.map(&%{name: String.trim(&1["name"]), per_side: "side" in List.wrap(&1["extra"])})
      end)
      |> Enum.reject(&(&1 == []))

    %{params: params, names: names}
  end

  defp truthy(value), do: value not in [nil, "", false]
  defp or_q(value), do: if(truthy(value), do: value, else: "?")
end
