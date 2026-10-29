defmodule Palee.Workouts.Domain.StructuredPlan.Notation do
  @moduledoc """
  The value notation of the structured WOD editor (ADR-270), pure.

  A port of the parsers the web editor uses (`apps/web/src/lib/structured-plan/parse.ts`,
  first written in `docs/product/mockups/structured-wod-parsers.js`), so the
  API reads what a coach typed exactly as the editor did:

  * `parse_clock/2` — one time ("2:00", "90″", "3'", "12"). A bare number is
    minutes with `:min`, or with `:smart` minutes up to 10 and seconds above.
  * `parse_times/1` — several times ("3-3-3-4" AMRAP windows, "90-120″" range).
  * `parse_dose/1` — reps or quantity ("12", "4×10", "12-10-8-8", "8-12",
    "5-10-15…", "400 m", "15 cal", "60s", "max", "/πλευρά").
  * `row_load_issues/1` — the load unit written once per row: bare numbers
    take the unit another column states; none anywhere, or a kg/% mix, is an
    issue. Words ("βαρύ", "με βάρος") are always fine.
  * `tempo?/1`, `relative?/1` for measures.

  Parsers return `nil` for an empty value and `:bad` for one that does not read.
  """

  @num "(\\d+(?:\\.\\d+)?(?::\\d{2})?)"
  @tempo ~r/^([0-9xX])-?([0-9xX])-?([0-9xX])-?([0-9xX])$/u
  @side ~r/\s*(\/\s*(side|πλευρά|πλευρα|πλ\.?|χέρι|χερι|πόδι|ποδι)|(on\s+)?each(\s+(side|arm|leg))?|for each arm|ανά πλευρά|ανα πλευρα|ανά χέρι|ανα χερι|ανά πόδι|ανα ποδι)$/u
  @unit ~r/\s*(reps|r|επ\.?|cal|kcal|θερμ\.?|km|m|sec|s|″|"|δ|min|'|′|λ)$/u
  @load_num ~r/^([+-]?\d+(?:\.\d+)?)\s*(%|kg)?(?:\s*(?:→|->|ως|έως)\s*(\d+(?:\.\d+)?)\s*(%|kg)?)?$/u

  @type range :: %{min: number(), max: number()}
  @type dose :: %{
          sets: range() | nil,
          entries: [range()] | nil,
          unit: :reps | :secs | :kcal | :m,
          per_side: boolean(),
          cont: boolean(),
          max: map() | nil
        }

  @doc "One time in seconds; `nil` when empty, `:bad` when it does not read."
  @spec parse_clock(String.t(), :min | :smart) :: non_neg_integer() | nil | :bad
  def parse_clock(text, default \\ :min) when is_binary(text) do
    value = text |> String.trim() |> String.downcase()

    cond do
      value == "" ->
        nil

      match = Regex.run(~r/^(\d+):(\d{2})$/u, value) ->
        [_all, minutes, seconds] = match
        String.to_integer(minutes) * 60 + String.to_integer(seconds)

      match = Regex.run(~r/^(\d+)\s*(s|sec|″|"|δ)$/u, value) ->
        match |> Enum.at(1) |> String.to_integer()

      match = Regex.run(~r/^(\d+)\s*(min|'|′|λ|λεπτά)$/u, value) ->
        String.to_integer(Enum.at(match, 1)) * 60

      match = Regex.run(~r/^(\d+)$/u, value) ->
        number = String.to_integer(Enum.at(match, 1))
        if default == :min or number <= 10, do: number * 60, else: number

      true ->
        :bad
    end
  end

  @doc "Several times (\"3-3-3-4\", \"90-120″\"): `%{range: bool, secs: [..]}`, `nil` or `:bad`."
  @spec parse_times(String.t(), :min | :smart) ::
          %{range: boolean(), secs: [pos_integer()]} | nil | :bad
  def parse_times(text, default \\ :min) when is_binary(text) do
    value = text |> String.trim() |> String.downcase()

    if value == "" do
      nil
    else
      unit =
        case Regex.run(~r/\s*(s|sec|″|"|δ|min|'|′|λ)$/u, value) do
          [_all, unit] -> unit
          nil -> nil
        end

      secs =
        value
        |> String.split(~r/\s*[-–,]\s*/u)
        |> Enum.map(fn part ->
          part = if unit && Regex.match?(~r/^\d+$/, part), do: part <> unit, else: part
          parse_clock(part, default)
        end)

      if Enum.all?(secs, &(is_integer(&1) and &1 > 0)) do
        range =
          length(secs) == 2 and not String.contains?(value, ",") and hd(secs) < List.last(secs)

        %{range: range, secs: secs}
      else
        :bad
      end
    end
  end

  @doc "A count (\"8\"): digits only."
  @spec count?(String.t()) :: boolean()
  def count?(text), do: Regex.match?(~r/^\d+$/, String.trim(text))

  @doc "A count or a range of counts (\"4\", \"3-4\")."
  @spec count_range?(String.t()) :: boolean()
  def count_range?(text), do: Regex.match?(~r/^\d+(\s*-\s*\d+)?$/, String.trim(text))

  @doc "The sets of a `sets` flow (\"4\", \"3-4\"): the most sets, or nil."
  @spec max_count(String.t() | nil) :: pos_integer() | nil
  def max_count(text) when is_binary(text) do
    case Regex.run(~r/^(\d+)(?:\s*-\s*(\d+))?$/, String.trim(text)) do
      [_all, min] -> positive(String.to_integer(min))
      [_all, _min, max] -> positive(String.to_integer(max))
      nil -> nil
    end
  end

  def max_count(_text), do: nil

  defp positive(number) when number > 0, do: number
  defp positive(_number), do: nil

  @doc "Numbers of a dose (\"12-10-8\", \"8-12\", \"5-10-15…\"): entries and whether they keep going."
  @spec parse_nums(String.t()) :: %{entries: [range()], cont: boolean()} | :bad
  def parse_nums(text) do
    {value, cont} =
      if Regex.match?(~r/(…|\.\.\.|\+)$/u, text),
        do: {text |> String.replace(~r/(…|\.\.\.|\+)$/u, "") |> String.trim(), true},
        else: {text, false}

    words = Regex.run(~r/^#{@num}\s*(?:έως|εως|to|~)\s*#{@num}$/u, value)

    cond do
      words ->
        [_all, min, max] = words
        %{entries: [%{min: to_num(min), max: to_num(max)}], cont: false}

      String.contains?(value, ",") ->
        comma_sets(value, cont)

      true ->
        dash_parts(value, cont)
    end
  end

  defp comma_sets(value, cont) do
    pattern = ~r/^#{@num}(?:\s*(?:[-–]|έως|εως|to)\s*#{@num})?$/u

    sets =
      value
      |> String.split(~r/\s*,\s*/u)
      |> Enum.map(fn part ->
        case Regex.run(pattern, part) do
          [_all, min] -> %{min: to_num(min), max: to_num(min)}
          [_all, min, max] -> %{min: to_num(min), max: to_num(max)}
          nil -> nil
        end
      end)

    if Enum.any?(sets, &(is_nil(&1) or &1.max < &1.min)) or (cont and length(sets) < 2),
      do: :bad,
      else: %{entries: sets, cont: cont}
  end

  defp dash_parts(value, cont) do
    parts = String.split(value, ~r/\s*[-–,]\s*/u)

    if Enum.all?(parts, &Regex.match?(~r/^#{@num}$/u, &1)) do
      nums = Enum.map(parts, &to_num/1)

      cond do
        cont and length(nums) < 2 ->
          :bad

        match?([_a, _b], nums) and not cont and hd(nums) < List.last(nums) ->
          %{entries: [%{min: hd(nums), max: List.last(nums)}], cont: cont}

        true ->
          %{entries: Enum.map(nums, &%{min: &1, max: &1}), cont: cont}
      end
    else
      :bad
    end
  end

  @doc "Reps or quantity of a row or a cell; `nil` when empty, `:bad` when it does not read."
  @spec parse_dose(String.t()) :: dose() | nil | :bad
  def parse_dose(text) when is_binary(text) do
    value = text |> String.trim() |> String.downcase() |> String.replace(~r/\s+/u, " ")

    if value == "" do
      nil
    else
      out = %{sets: nil, entries: nil, unit: :reps, per_side: false, cont: false, max: nil}

      {value, out} =
        case Regex.run(@side, value, return: :index) do
          [{at, _length} | _groups] ->
            {value |> binary_part(0, at) |> String.trim(), %{out | per_side: true}}

          nil ->
            {value, out}
        end

      dose_sets(value, out)
    end
  end

  defp dose_sets(value, out) do
    case Regex.run(~r/^(\d+)(?:\s*-\s*(\d+))?\s*(?:sets?|σετ)?\s*[x×χ]\s*(.*)$/u, value) do
      [_all, min, max, rest] ->
        min = String.to_integer(min)
        max = if max == "", do: min, else: String.to_integer(max)

        cond do
          min == 0 or max < min -> :bad
          String.trim(rest) == "" -> %{out | sets: %{min: min, max: max}}
          true -> dose_body(String.trim(rest), %{out | sets: %{min: min, max: max}})
        end

      nil ->
        dose_body(value, out)
    end
  end

  defp dose_body(value, out) do
    case Regex.run(~r/^(?:(\S+)\s+)?(max|μέγιστ\S*)\s*(reps|cal|m)?$/u, value) do
      [_all | groups] -> dose_max(groups, out)
      nil -> dose_numbers(value, out)
    end
  end

  defp dose_max(groups, out) do
    [within, _word | rest] = groups ++ [""]
    within = if within == "", do: nil, else: parse_clock(within, :smart)

    unit =
      case rest do
        ["cal" | _rest] -> :kcal
        ["m" | _rest] -> :m
        _other -> :reps
      end

    if within == :bad, do: :bad, else: %{out | max: %{within: within}, unit: unit}
  end

  defp dose_numbers(value, out) do
    {value, unit, scale} =
      case Regex.run(@unit, value, return: :index) do
        [{at, _length}, {unit_at, unit_length}] ->
          unit = binary_part(value, unit_at, unit_length)
          {unit, scale} = dose_unit(unit)
          {value |> binary_part(0, at) |> String.trim(), unit, scale}

        nil ->
          {value, :reps, 1}
      end

    unit = if String.contains?(value, ":"), do: :secs, else: unit

    case parse_nums(value) do
      :bad ->
        :bad

      %{entries: entries, cont: cont} ->
        entries = Enum.map(entries, &%{min: &1.min * scale, max: &1.max * scale})

        cond do
          Enum.any?(entries, &(&1.min <= 0)) -> :bad
          out.sets && (length(entries) > 1 or cont) -> :bad
          true -> %{out | entries: entries, cont: cont, unit: unit}
        end
    end
  end

  defp dose_unit(unit) when unit in ["cal", "kcal", "θερμ", "θερμ."], do: {:kcal, 1}
  defp dose_unit("m"), do: {:m, 1}
  defp dose_unit("km"), do: {:m, 1000}
  defp dose_unit(unit) when unit in ["sec", "s", "″", "\"", "δ"], do: {:secs, 1}
  defp dose_unit(unit) when unit in ["min", "'", "′", "λ"], do: {:secs, 60}
  defp dose_unit(_reps), do: {:reps, 1}

  @doc """
  The load unit of a row, written once (kg or %), and the columns whose load
  breaks the rule: `%{unit: "kg" | "%" | nil, issues: %{index => :missing_unit | :mixed_unit}}`.
  Empty columns and words never have an issue.
  """
  @spec row_load_issues([String.t() | nil]) :: %{unit: String.t() | nil, issues: map()}
  def row_load_issues(loads) do
    matches =
      Enum.map(loads, fn load ->
        raw = load_raw(load)
        {raw, raw != "" && Regex.run(@load_num, raw)}
      end)

    unit = Enum.find_value(matches, fn {_raw, match} -> stated_unit(match) end)

    issues =
      matches
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn
        {{"", _match}, _index}, acc -> acc
        {{_raw, false}, _index}, acc -> acc
        {{_raw, nil}, _index}, acc -> acc
        {{_raw, match}, index}, acc -> load_issue(match, unit, index, acc)
      end)

    %{unit: unit, issues: issues}
  end

  defp load_issue(match, unit, index, acc) do
    stated = stated_unit(match)

    cond do
      is_nil(unit) -> Map.put(acc, index, :missing_unit)
      stated && stated != unit -> Map.put(acc, index, :mixed_unit)
      true -> acc
    end
  end

  @doc "The first load of a row as a value the legacy columns hold, or nil."
  @spec first_load(String.t() | nil, String.t() | nil) ::
          %{value: number() | nil, mode: :absolute | :pct_1rm | :bw} | nil
  def first_load(load, row_unit) do
    raw = load_raw(load)

    cond do
      raw in ["bw", "σβ", "body", "bodyweight", "σωματικό βάρος"] ->
        %{value: nil, mode: :bw}

      match = raw != "" && Regex.run(@load_num, raw) ->
        unit = stated_unit(match) || row_unit
        number = match |> Enum.at(1) |> to_num()

        cond do
          String.starts_with?(Enum.at(match, 1), ["+", "-"]) -> nil
          unit == "kg" -> %{value: number, mode: :absolute}
          unit == "%" -> %{value: number, mode: :pct_1rm}
          true -> nil
        end

      true ->
        nil
    end
  end

  defp load_raw(load) when is_binary(load) do
    load
    |> String.trim()
    |> String.downcase()
    |> String.replace(",", ".", global: false)
    |> String.replace(~r/κιλ[άα]?/u, "kg", global: false)
  end

  defp load_raw(_load), do: ""

  defp stated_unit(match) when is_list(match) do
    case Enum.at(match, 4) do
      unit when unit in ["kg", "%"] -> unit
      _none -> if Enum.at(match, 2) in ["kg", "%"], do: Enum.at(match, 2), else: nil
    end
  end

  defp stated_unit(_match), do: nil

  @doc """
  Load or intensity as written in one field: `%{kind: :bw}`, `%{kind: :rpe, min, max}`,
  `%{kind: :zone, zone}`, `%{kind: :pace, per, secs}`, `%{kind: :kg | :pct, entries, up}`
  or `%{kind: :text, text}`. Never fails: anything else is the coach's words.
  """
  @spec parse_load(String.t() | nil) :: map() | nil
  def parse_load(text) when is_binary(text) do
    value = text |> String.trim() |> String.downcase() |> String.replace(~r/\s+/u, " ")

    cond do
      value == "" ->
        nil

      value in ["bw", "σβ", "body", "bodyweight", "σωματικό βάρος"] ->
        %{kind: :bw}

      match = Regex.run(~r/^rpe\s*(\d+(?:\.\d)?)(?:\s*-\s*(\d+(?:\.\d)?))?$/u, value) ->
        [_all, min | rest] = match
        %{kind: :rpe, min: to_num(min), max: to_num(List.first(rest) || min)}

      match = Regex.run(~r/^(?:z|zone|ζώνη|ζωνη)\s*([1-5])$/u, value) ->
        %{kind: :zone, zone: String.to_integer(Enum.at(match, 1))}

      match = Regex.run(~r/^(\d+:\d{2})\s*\/\s*(500m|500|km|100m|mi)$/u, value) ->
        [_all, secs, per] = match
        %{kind: :pace, per: if(per == "500", do: "500m", else: per), secs: to_num(secs)}

      true ->
        amount_load(value, String.trim(text))
    end
  end

  def parse_load(_text), do: nil

  defp amount_load(value, original) do
    {value, up} =
      if Regex.match?(~r/(\+|↑)$/u, value),
        do: {value |> String.replace(~r/(\+|↑)$/u, "") |> String.trim(), true},
        else: {value, false}

    with [{at, _length}, {unit_at, unit_length}] <-
           Regex.run(~r/\s*(kg|κιλά|κιλα|%)$/u, value, return: :index),
         numbers =
           value
           |> binary_part(0, at)
           |> String.trim()
           |> String.replace(~r/(\d),(\d)$/u, "\\1.\\2"),
         %{entries: entries, cont: false} <- parse_nums(numbers) do
      kind = if binary_part(value, unit_at, unit_length) == "%", do: :pct, else: :kg
      %{kind: kind, entries: entries, up: up}
    else
      _words -> %{kind: :text, text: original}
    end
  end

  @doc "A tempo: four marks, digits or X (\"31X1\", \"3-1-X-1\")."
  @spec tempo?(String.t()) :: boolean()
  def tempo?(text), do: Regex.match?(@tempo, String.trim(text))

  @doc "A tempo's four marks (seconds, or \"X\" = explosive), or nil."
  @spec tempo_parts(String.t()) :: %{down: mark, bottom: mark, up: mark, top: mark} | nil
        when mark: non_neg_integer() | String.t()
  def tempo_parts(text) do
    case Regex.run(@tempo, String.trim(text)) do
      [_all, down, bottom, up, top] ->
        %{down: mark(down), bottom: mark(bottom), up: mark(up), top: mark(top)}

      nil ->
        nil
    end
  end

  defp mark(char) when char in ["x", "X"], do: "X"
  defp mark(char), do: String.to_integer(char)

  @doc "A value relative to the column before (\"+5\", \"-0:05\") or spread to the last (\"60→80\")."
  @spec relative?(String.t()) :: boolean()
  def relative?(text), do: Regex.match?(~r/^[+-]|→|->|ως|έως/u, String.trim(text))

  @doc "A number as typed (\"12\", \"22.5\", \"1:30\" = 90)."
  @spec to_num(String.t()) :: number()
  def to_num(text) do
    case String.split(text, ":") do
      [minutes, seconds] ->
        String.to_integer(minutes) * 60 + String.to_integer(seconds)

      [number] ->
        if String.contains?(number, "."),
          do: String.to_float(normalize_float(number)),
          else: String.to_integer(number)
    end
  end

  defp normalize_float("+" <> number), do: normalize_float(number)
  defp normalize_float("." <> _rest = number), do: "0" <> number
  defp normalize_float(number), do: number
end
