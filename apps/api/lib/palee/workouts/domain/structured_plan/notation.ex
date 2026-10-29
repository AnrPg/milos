defmodule Palee.Workouts.Domain.StructuredPlan.Notation do
  @moduledoc """
  The value notation of the structured WOD editor (ADR-270), pure: a port of
  `apps/web/src/lib/structured-plan/parse.ts`, rule for rule, so the API
  reads what a coach typed exactly as the editor does. The grammar is
  `docs/product/structured-wod-notation.md`; the shared corpus
  (`test/support/fixtures/structured_plan_corpus.json`) keeps both sides equal.

  * `norm_text/1` — the form every rule reads: trimmed, lower case, Greek
    accents removed, spaces collapsed, every dash `-`, minute marks `′`,
    second marks `″`, `...` `…`, `->` / `=>` `→`; `decimal_comma/1` turns
    `22,5` into `22.5` (a comma followed by exactly one digit).
  * times: `parse_clock/2`, `parse_times/2`, `clock_ambiguity/2`; counts:
    `parse_count/1`, `parse_count_range/1`.
  * values: `parse_nums/1`, `parse_dose/1`, `parse_load/1` (with the
    `ambiguous` reading of `10-12`, `60-70%`, `5-10-15`), `entry_at/2`.
  * columns: `set_loads/2` (the load unit written once per row, `+x`,
    `a→b`, `no_base`), `set_load_readings/2` (the same, as numbers),
    `progress/4` and `progress_readings/4` (measures), `measure_cell_errors/4`,
    `repeat_text/3`.
  * `tempo_parts/1`, `tempo_canonical/1`; `show_entry/2`, `show_dose_at/2`,
    `clock/1`, `num_str/1` (the editor's display forms).

  Every function takes any value and never raises. Parsers return `nil` for
  an empty value and `:bad` for one that does not read. Numbers are integers
  when written whole and floats otherwise (`22.5`).
  """

  @max_number 1_000_000_000
  @max_count 999

  def max_number, do: @max_number
  def max_count, do: @max_count

  @unit_words %{
    secs: ~w(s sec secs second seconds ″ δ δευτ δευτ. δευτερολεπτο δευτερολεπτα),
    mins: ~w(min mins minute minutes ′ λ λ. λεπτ λεπτ. λεπτο λεπτα),
    reps: ~w(reps rep r επαναληψεις επαναληψη επαν επαν. επ επ.),
    kcal: ~w(cal cals kcal calories θερμιδες θερμ θερμ.),
    m: ~w(m meters metres μ μ. μετρα),
    km: ~w(km χλμ χλμ.),
    kg: ~w(kg kgs kgr κιλα κιλο κ κ.),
    pct: ~w(%)
  }

  def unit_words, do: @unit_words

  # An alternation of words, longest first (UTF-16 length, stable), as a regex source.
  alt = fn words ->
    words
    |> Enum.sort_by(&(-div(byte_size(:unicode.characters_to_binary(&1, :utf8, :utf16)), 2)))
    |> Enum.map_join("|", &Regex.escape/1)
  end

  @sec_re alt.(@unit_words.secs)
  @min_re alt.(@unit_words.mins)
  @kg_re alt.(@unit_words.kg)
  @load_unit_re "#{@kg_re}|%"
  @range_words "εως|ως|to|~"
  @num "([0-9]+(?:\\.[0-9]+)?(?::[0-5][0-9])?)"
  @ln "([0-9]+(?:\\.[0-9]+)?)"
  @lu "\\s*(#{@load_unit_re})?"

  @dose_units [
    {@unit_words.reps, "reps", 1},
    {@unit_words.kcal, "kcal", 1},
    {@unit_words.km, "m", 1000},
    {@unit_words.m, "m", 1},
    {@unit_words.secs, "secs", 1},
    {@unit_words.mins, "secs", 60}
  ]
  @dose_unit_re alt.(Enum.flat_map(@dose_units, &elem(&1, 0)))
  @max_unit Map.new(
              Enum.map(@unit_words.reps, &{&1, "reps"}) ++
                Enum.map(@unit_words.kcal, &{&1, "kcal"}) ++
                Enum.map(@unit_words.m, &{&1, "m"})
            )
  @max_unit_re alt.(Map.keys(@max_unit))
  @not_load_unit_re alt.(
                      @unit_words.km ++
                        @unit_words.m ++
                        @unit_words.kcal ++
                        @unit_words.reps ++ @unit_words.secs ++ @unit_words.mins
                    )

  @bw ["bw", "σβ", "body", "bodyweight", "body weight", "σωματικο βαρος", "βαρος σωματος"]

  # JS-like regexes: UTF-8, ASCII \d and \s (the text is normalised first).
  defp re(source), do: Regex.compile!(source, [:unicode])

  # ── normalisation ──────────────────────────────────────

  @doc "The form every rule reads (see the module doc). Anything but a string is \"\"."
  @spec norm_text(term()) :: String.t()
  def norm_text(text) when is_binary(text) do
    if String.valid?(text) do
      text
      |> :unicode.characters_to_nfd_binary()
      |> then(&Regex.replace(~r/[\x{0300}-\x{036F}]/u, &1, ""))
      |> String.downcase(:greek)
      |> then(&Regex.replace(~r/[\x{2010}-\x{2015}\x{2212}\x{FE58}\x{FE63}\x{FF0D}]/u, &1, "-"))
      |> then(&Regex.replace(~r/(?:''|′′|[“”„"])/u, &1, "″"))
      |> then(&Regex.replace(~r/[’‘'`´]/u, &1, "′"))
      |> String.replace("...", "…")
      |> then(&Regex.replace(~r/\s*(?:->|=>)\s*/u, &1, "→"))
      |> then(&Regex.replace(~r/\s+/u, &1, " "))
      |> String.trim()
    else
      ""
    end
  end

  def norm_text(_text), do: ""

  @doc "\"22,5\" → \"22.5\": a comma followed by exactly one digit is a decimal point."
  @spec decimal_comma(String.t()) :: String.t()
  def decimal_comma(value), do: Regex.replace(~r/([0-9]),([0-9])(?![0-9])/, value, "\\1.\\2")

  @doc "`norm_text/1` plus the decimal comma rule."
  @spec decimal_comma_norm(term()) :: String.t()
  def decimal_comma_norm(text), do: text |> norm_text() |> decimal_comma()

  # ── numbers and formatting ─────────────────────────────

  @doc "A number as typed: \"12\" → 12, \"22.5\" → 22.5, \"1:30\" → 90."
  @spec to_num(String.t()) :: number()
  def to_num(text) do
    case String.split(text, ":") do
      [minutes, seconds] -> number(minutes) * 60 + number(seconds)
      [value] -> number(value)
      _other -> 0
    end
  end

  defp number(text) do
    text = String.trim_leading(text, "+")

    cond do
      String.contains?(text, ".") ->
        case Float.parse(if String.starts_with?(text, "."), do: "0" <> text, else: text) do
          {value, ""} -> value
          _other -> 0
        end

      true ->
        case Integer.parse(text) do
          {value, ""} -> value
          _other -> 0
        end
    end
  end

  # Math.round: half up.
  defp js_round(value) when is_integer(value), do: value
  defp js_round(value), do: value |> Kernel.+(0.5) |> Float.floor() |> trunc()

  defp whole(value) when is_float(value) and value == trunc(value) and abs(value) < 1.0e15,
    do: trunc(value)

  defp whole(value), do: value

  defp js_string(value) when is_integer(value), do: Integer.to_string(value)

  defp js_string(value) when is_float(value) do
    if value == trunc(value) and abs(value) < 1.0e15,
      do: Integer.to_string(trunc(value)),
      else: Float.to_string(value)
  end

  @doc "A number with at most two decimals, no trailing zeros (\"22.5\", \"60\")."
  @spec num_str(number()) :: String.t()
  def num_str(n), do: js_string(round_to(n, 100))

  defp round_to(n, _factor) when is_integer(n), do: n
  defp round_to(n, factor), do: whole(js_round(n * factor) / factor)

  defp fmod(a, b) when is_integer(a) and is_integer(b), do: rem(a, b)
  defp fmod(a, b), do: a - b * Float.floor(a / b)

  defp pad2(n), do: n |> js_round() |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc "\"1:30\" from 90 seconds, \"45″\" below a minute."
  @spec clock(number()) :: String.t()
  def clock(secs) when secs >= 60, do: "#{trunc(Float.floor(secs / 60))}:#{pad2(fmod(secs, 60))}"
  def clock(secs), do: "#{num_str(secs)}″"

  @doc "Always \"m:ss\"."
  @spec mmss(number()) :: String.t()
  def mmss(secs), do: "#{trunc(Float.floor(secs / 60))}:#{pad2(fmod(secs, 60))}"

  # ── time fields ────────────────────────────────────────

  @clock_mss ~r/^([0-9]+):([0-5][0-9])$/
  @min_sec_re "^([0-9]+)\\s*(?:#{@min_re})\\s*([0-9]+)\\s*(?:#{@sec_re})?$"
  @sec_only_re "^([0-9]+(?:\\.[0-9]+)?)\\s*(?:#{@sec_re})$"
  @min_only_re "^([0-9]+(?:\\.[0-9]+)?)\\s*(?:#{@min_re})$"

  defp read_clock(v, dflt) do
    case read_clock_raw(v, dflt) do
      %{secs: secs} when secs > @max_number -> :bad
      other -> other
    end
  end

  defp read_clock_raw(v, dflt) do
    cond do
      m = Regex.run(@clock_mss, v) ->
        [_all, a, b] = m
        %{secs: to_num(a) * 60 + to_num(b), assumed: nil}

      (m = Regex.run(re(@min_sec_re), v)) && to_num(Enum.at(m, 2)) < 60 ->
        %{secs: to_num(Enum.at(m, 1)) * 60 + to_num(Enum.at(m, 2)), assumed: nil}

      m = Regex.run(re(@sec_only_re), v) ->
        %{secs: js_round(to_num(Enum.at(m, 1))), assumed: nil}

      m = Regex.run(re(@min_only_re), v) ->
        %{secs: js_round(to_num(Enum.at(m, 1)) * 60), assumed: nil}

      m = Regex.run(~r/^([0-9]+)$/, v) ->
        n = to_num(Enum.at(m, 1))

        if dflt == :min or n <= 10,
          do: %{secs: n * 60, assumed: :min},
          else: %{secs: n, assumed: :sec}

      true ->
        :bad
    end
  end

  @doc """
  One duration in seconds: \"1:30\", \"90s\", \"90″\", \"2′\", \"2 λεπτά\",
  \"1.5 min\", \"2′30″\". A bare number is minutes with `:min`; with `:smart`
  minutes up to 10 and seconds above. Empty → nil, unreadable → `:bad`.
  """
  @spec parse_clock(term(), :min | :smart) :: number() | nil | :bad
  def parse_clock(text, dflt \\ :min) do
    case decimal_comma_norm(text) do
      "" ->
        nil

      v ->
        case read_clock(v, dflt) do
          :bad -> :bad
          %{secs: secs} -> secs
        end
    end
  end

  @doc "How a bare number in a time field was read, and the other reading; nil when the unit is written."
  @spec clock_ambiguity(term(), :min | :smart) :: map() | nil
  def clock_ambiguity(text, dflt \\ :min) do
    v = norm_text(text)
    r = if v == "", do: :bad, else: read_clock(v, dflt)

    case r do
      %{assumed: assumed, secs: secs} when assumed != nil ->
        {alt, write} =
          if assumed == :min, do: {"seconds", "#{to_num(v)}″"}, else: {"minutes", "#{to_num(v)}′"}

        %{
          alt: alt,
          write: write,
          hint: %{key: "PlanCore.ambiguous.clock", values: %{reading: clock(secs), write: write}}
        }

      _other ->
        nil
    end
  end

  @times_unit_re "\\s*(#{@sec_re}|#{@min_re})$"

  @doc """
  Several durations: AMRAP windows (\"3-3-3-4\", \"3, 3, 3, 4\", \"3/3/3/4\")
  or a range (\"90-120″\"): `%{range: boolean, secs: [..]}`, nil or `:bad`.
  """
  @spec parse_times(term(), :min | :smart) :: %{range: boolean(), secs: [number()]} | nil | :bad
  def parse_times(text, dflt \\ :min) do
    case decimal_comma_norm(text) do
      "" -> nil
      v -> times(v, dflt)
    end
  end

  defp times(v, dflt) do
    um = Regex.run(re(@times_unit_re), v)
    raw = String.split(v, ~r/\s*[-,\/]\s*/)

    if Enum.any?(raw, &(&1 == "")) do
      :bad
    else
      bare = raw |> Enum.filter(&Regex.match?(~r/^[0-9]+$/, &1)) |> Enum.map(&to_num/1)

      shared =
        if is_nil(um) and dflt == :smart and length(bare) > 1,
          do: if(Enum.any?(bare, &(&1 > 10)), do: "″", else: "′")

      parts =
        Enum.map(raw, fn part ->
          if Regex.match?(~r/^[0-9]+$/, part),
            do: part <> ((um && Enum.at(um, 1)) || shared || ""),
            else: part
        end)

      secs = Enum.map(parts, &read_clock(&1, dflt))

      if Enum.any?(secs, &(&1 == :bad or &1.secs <= 0)) do
        :bad
      else
        nums = Enum.map(secs, & &1.secs)

        range =
          length(nums) == 2 and not Regex.match?(~r/[,\/]/, v) and hd(nums) < List.last(nums)

        %{range: range, secs: nums}
      end
    end
  end

  @doc "A whole positive count up to #{@max_count}, or nil."
  @spec parse_count(term()) :: pos_integer() | nil
  def parse_count(text) do
    v = norm_text(text)

    if Regex.match?(~r/^[0-9]+$/, v) do
      n = to_num(v)
      if n > 0 and n <= @max_count, do: n
    end
  end

  @doc "A count or a count range: \"4\", \"3-4\", \"3 ή 4\", \"3 or 4\", \"3/4\"; nil when unreadable."
  @spec parse_count_range(term()) :: %{min: pos_integer(), max: pos_integer()} | nil
  def parse_count_range(text) do
    case Regex.run(
           re("^([0-9]+)(?:\\s*(?:-|\\/|η|or|εως|to)\\s*([0-9]+))?$"),
           norm_text(text)
         ) do
      nil ->
        nil

      [_all, a | rest] ->
        min = to_num(a)
        max = if rest in [[], [""]], do: min, else: to_num(hd(rest))
        if min > 0 and max >= min and max <= @max_count, do: %{min: min, max: max}
    end
  end

  # ── number lists ───────────────────────────────────────

  @doc """
  A list of numbers: \"12-10-8-8\" (per set), \"8-12\" (two ascending: a range,
  `ambiguous: \"list\"`), \"8-10, 6-8\", \"8 έως 12\", \"5-10-15…\" (keeps going);
  a rising list \"5-10-15\" is `ambiguous: \"ladder\"`.
  """
  @spec parse_nums(term()) :: map() | :bad
  def parse_nums(text) do
    v = norm_text(text)

    {v, cont} =
      if Regex.match?(~r/(…|\+)$/u, v),
        do: {v |> String.replace(~r/(…|\+)$/u, "") |> String.trim(), true},
        else: {v, false}

    cond do
      v == "" ->
        :bad

      words = Regex.run(re("^#{@num}\\s*(?:#{@range_words})\\s*#{@num}$"), v) ->
        nums_words(words, cont)

      String.contains?(v, ",") ->
        nums_commas(v, cont)

      true ->
        nums_dashes(v, cont)
    end
  end

  defp nums_words([_all, a, b], cont) do
    {a, b} = {to_num(a), to_num(b)}

    if a <= b and b <= @max_number and not cont,
      do: %{entries: [%{min: a, max: b}], cont: false},
      else: :bad
  end

  defp nums_commas(v, cont) do
    one = re("^#{@num}(?:\\s*(?:-|#{@range_words})\\s*#{@num})?$")

    sets =
      v
      |> String.split(~r/\s*,\s*/)
      |> Enum.map(fn part ->
        case Regex.run(one, part) do
          [_all, a] -> %{min: to_num(a), max: to_num(a)}
          [_all, a, b] -> %{min: to_num(a), max: to_num(b)}
          nil -> nil
        end
      end)

    if Enum.any?(sets, &(is_nil(&1) or &1.max < &1.min or &1.max > @max_number)) or
         (cont and length(sets) < 2),
       do: :bad,
       else: %{entries: sets, cont: cont}
  end

  defp nums_dashes(v, cont) do
    parts = String.split(v, ~r/\s*-\s*/)
    whole = re("^#{@num}$")

    if Enum.all?(parts, &Regex.match?(whole, &1)) do
      nums = Enum.map(parts, &to_num/1)

      cond do
        cont and length(nums) < 2 ->
          :bad

        Enum.any?(nums, &(&1 > @max_number)) ->
          :bad

        match?([_a, _b], nums) and hd(nums) < List.last(nums) and not cont ->
          %{entries: [%{min: hd(nums), max: List.last(nums)}], cont: cont, ambiguous: "list"}

        true ->
          out = %{entries: Enum.map(nums, &%{min: &1, max: &1}), cont: cont}
          if not cont and ladder?(nums), do: Map.put(out, :ambiguous, "ladder"), else: out
      end
    else
      :bad
    end
  end

  defp ladder?([a, b | _rest] = nums) when length(nums) >= 3 do
    step = b - a

    step > 0 and
      nums |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [x, y] -> y - x == step end)
  end

  defp ladder?(_nums), do: false

  # "30s-45s", "60kg-70kg" → one unit at the end (already removed by the caller).
  defp strip_repeated_unit(v, unit_re) do
    Regex.replace(
      re("([0-9])\\s*(?:#{unit_re})(?=\\s*(?:-|,|#{@range_words}|$))"),
      v,
      "\\1"
    )
  end

  # ── dose ───────────────────────────────────────────────

  @side_re "\\s*(?:\\/\\s*(?:side|leg|arm|πλευρα|πλ\\.?|χερι|ποδι)|(?:on\\s+)?each(?:\\s+(?:side|arm|leg))?|for each (?:side|arm|leg)|per (?:side|arm|leg)|e\\/s|ανα (?:πλευρα|χερι|ποδι))$"
  @sets_x_re "^([0-9]+)(?:\\s*-\\s*([0-9]+))?\\s*(?:sets?|σετ)?\\s*[x×χ*]\\s*(?=$|[0-9]|max|amrap|μεγιστ)(.*)$"
  @max_re "^(?:(\\S+)\\s+)?(?:max|amrap|μεγιστ\\S*)(?:\\s*(#{@max_unit_re}))?(?:\\s+(?:in|σε)\\s+(\\S+))?$"

  @doc """
  Reps or quantity: \"10\", \"4×10\", \"12-10-8-8\", \"8-10\", \"3-4×12-15\",
  \"5-10-15…\", \"30-45s\", \"1:00\", \"500m\", \"2km\", \"15 cal\", \"max\",
  \"60s max cal\", \"max cal σε 1:00\", \"8-10 each side\". A map with `sets`,
  `entries`, `unit` (reps | kcal | m | secs), `per_side`, `cont`, `max`
  (`%{within: secs | nil}`) and maybe `ambiguous`; nil or `:bad`.
  """
  @spec parse_dose(term()) :: map() | nil | :bad
  def parse_dose(text) do
    case decimal_comma_norm(text) do
      "" ->
        nil

      v ->
        out = %{sets: nil, entries: nil, unit: "reps", per_side: false, cont: false, max: nil}

        {v, out} =
          case Regex.run(re(@side_re), v, return: :index) do
            [{at, _len} | _groups] ->
              {v |> binary_part(0, at) |> String.trim(), %{out | per_side: true}}

            nil ->
              {v, out}
          end

        dose_sets(v, out)
    end
  end

  defp dose_sets(v, out) do
    case Regex.run(re(@sets_x_re), v) do
      [_all, a, b, rest] ->
        min = to_num(a)
        max = if b == "", do: min, else: to_num(b)
        out = %{out | sets: %{min: min, max: max}}
        rest = String.trim(rest)

        cond do
          min == 0 or max < min or max > @max_count -> :bad
          rest == "" -> out
          true -> dose_max(rest, out)
        end

      nil ->
        dose_max(v, out)
    end
  end

  defp dose_max(v, out) do
    case Regex.run(re(@max_re), v) do
      nil ->
        dose_numbers(v, out)

      m ->
        [before, unit, after_] = m |> tl() |> Kernel.++(["", "", ""]) |> Enum.take(3)

        if before != "" and after_ != "" do
          :bad
        else
          t = if before != "", do: before, else: after_
          within = if t != "", do: parse_clock(t, :smart)

          if within in [:bad, 0],
            do: :bad,
            else: %{
              out
              | max: %{within: within},
                unit: if(unit != "", do: @max_unit[unit], else: "reps")
            }
        end
    end
  end

  defp dose_numbers(v, out) do
    {v, out, scale, unit_written?} =
      case Regex.run(re("\\s*(#{@dose_unit_re})$"), v, return: :index) do
        [{at, _len}, {unit_at, unit_len}] ->
          word = binary_part(v, unit_at, unit_len)
          {unit, scale} = dose_unit_of(word)

          v =
            v
            |> binary_part(0, at)
            |> String.trim()
            |> strip_repeated_unit(Regex.escape(word))

          {v, %{out | unit: unit}, scale, true}

        nil ->
          {v, out, 1, false}
      end

    cond do
      String.contains?(v, ":") and unit_written? and out.unit != "secs" -> :bad
      String.contains?(v, ":") -> dose_entries(v, %{out | unit: "secs"}, 1)
      true -> dose_entries(v, out, scale)
    end
  end

  defp dose_entries(v, out, scale) do
    case parse_nums(v) do
      :bad ->
        :bad

      p ->
        entries = Enum.map(p.entries, &%{min: &1.min * scale, max: &1.max * scale})
        out = %{out | entries: entries, cont: p.cont}

        cond do
          Enum.any?(entries, &(&1.min <= 0 or &1.max > @max_number)) ->
            :bad

          out.sets && (length(entries) > 1 or p.cont) ->
            :bad

          out.sets ->
            out

          true ->
            case ambiguity_of(Map.put(p, :entries, entries), out.unit) do
              nil -> out
              amb -> Map.put(out, :ambiguous, amb)
            end
        end
    end
  end

  defp dose_unit_of(word) do
    Enum.find_value(@dose_units, {"reps", 1}, fn {words, unit, scale} ->
      if word in words, do: {unit, scale}
    end)
  end

  defp ambiguity_of(%{ambiguous: "list", entries: [e | _rest]}, unit) do
    write = Enum.map_join([e.min, e.max], ", ", &show_one(&1, unit))

    %{
      alt: "list",
      write: write,
      hint: %{
        key: "PlanCore.ambiguous.rangeOrList",
        values: %{range: show_entry(e, unit), count: 2, write: write}
      }
    }
  end

  defp ambiguity_of(%{ambiguous: "ladder", entries: entries}, unit) do
    write = Enum.map_join(entries, "-", &num_str(&1.min)) <> "…" <> unit_suffix(unit)

    %{
      alt: "ladder",
      write: write,
      hint: %{
        key: "PlanCore.ambiguous.listOrLadder",
        values: %{list: Enum.map_join(entries, " · ", &show_one(&1.min, unit)), write: write}
      }
    }
  end

  defp ambiguity_of(_nums, _unit), do: nil

  defp unit_suffix("kcal"), do: " cal"
  defp unit_suffix("m"), do: " m"
  defp unit_suffix("secs"), do: "″"
  defp unit_suffix("kg"), do: " kg"
  defp unit_suffix("pct"), do: "%"
  defp unit_suffix(_unit), do: ""

  @doc "How many sets a dose implies (its own \"4×\", or one per listed value)."
  @spec set_count_of(term()) :: pos_integer()
  def set_count_of(%{sets: %{max: max}}), do: max
  def set_count_of(%{entries: [_ | _] = entries}), do: length(entries)
  def set_count_of(_dose), do: 1

  @doc "The dose's value for set / round `i` (0-based); \"5-10-15…\" keeps adding the last step."
  @spec entry_at(term(), non_neg_integer()) :: %{min: number(), max: number()} | nil
  def entry_at(%{entries: [only]}, _i), do: only

  def entry_at(%{entries: [_, _ | _] = entries, cont: cont}, i) do
    count = length(entries)

    cond do
      i < count ->
        Enum.at(entries, i)

      cont ->
        [a, b] = Enum.take(entries, -2)
        n = b.min + (b.min - a.min) * (i - count + 1)
        %{min: n, max: n}

      true ->
        List.last(entries)
    end
  end

  def entry_at(_dose, _i), do: nil

  # ── load ───────────────────────────────────────────────

  defp norm_load_text(text) do
    text
    |> decimal_comma_norm()
    |> then(&Regex.replace(~r/^@\s*/, &1, ""))
    |> then(&Regex.replace(re("%\\s*(?:(?:του|of)\\s*)?1\\s*rm$"), &1, "%"))
  end

  @doc """
  Load or intensity in one field: `%{kind: \"bw\"}`, `%{kind: \"rpe\", min, max}`,
  `%{kind: \"zone\", zone}`, `%{kind: \"pace\", per, secs}`,
  `%{kind: \"kg\" | \"pct\", entries, up}` (maybe `ambiguous`), `%{kind: \"wrong\", text}`
  (a number with a unit that is not a load) or `%{kind: \"text\", text}`; nil when empty.
  """
  @spec parse_load(term()) :: map() | nil
  def parse_load(text) do
    v = norm_load_text(text)
    raw = if is_binary(text), do: String.trim(text), else: ""

    cond do
      v == "" ->
        nil

      v in @bw ->
        %{kind: "bw"}

      m =
          Regex.run(
            ~r/^(?:rpe\s*|@\s*)([0-9]+(?:\.[0-9])?)(?:\s*-\s*([0-9]+(?:\.[0-9])?))?$/,
            if(String.starts_with?(raw, "@"), do: "@" <> v, else: v)
          ) ->
        [_all, a | rest] = m
        b = if rest in [[], [""]], do: a, else: hd(rest)
        %{kind: "rpe", min: to_num(a), max: to_num(b)}

      m = Regex.run(re("^(?:z|zone|ζωνη)\\s*([1-5])$"), v) ->
        %{kind: "zone", zone: to_num(Enum.at(m, 1))}

      m = Regex.run(~r/^([0-9]+:[0-5][0-9])\s*\/\s*(500m|500|1km|km|100m|mi)$/, v) ->
        [_all, secs, per] = m
        per = %{"500" => "500m", "1km" => "km"}[per] || per
        %{kind: "pace", per: per, secs: to_num(secs)}

      not_load_unit?(v) ->
        %{kind: "wrong", text: raw}

      true ->
        amount_load(v, raw)
    end
  end

  defp not_load_unit?(v),
    do: Regex.match?(re("^[+-]?[0-9]+(?:\\.[0-9]+)?\\s*(?:#{@not_load_unit_re})$"), v)

  defp amount_load(v, raw) do
    {v, up} =
      if Regex.match?(~r/(\+|↑)$/u, v),
        do: {v |> String.slice(0..-2//1) |> String.trim(), true},
        else: {v, false}

    with [{at, _len}, {unit_at, unit_len}] <-
           Regex.run(re("\\s*(#{@load_unit_re})$"), v, return: :index),
         word = binary_part(v, unit_at, unit_len),
         kind = if(word == "%", do: "pct", else: "kg"),
         %{cont: false} = n <-
           v
           |> binary_part(0, at)
           |> String.trim()
           |> strip_repeated_unit(Regex.escape(word))
           |> parse_nums() do
      out = %{kind: kind, entries: n.entries, up: up}

      case if(up, do: nil, else: ambiguity_of(n, kind)) do
        nil -> out
        amb -> Map.put(out, :ambiguous, amb)
      end
    else
      _words -> %{kind: "text", text: raw}
    end
  end

  # ── display ────────────────────────────────────────────

  defp show_one(n, "secs"), do: clock(n)
  defp show_one(n, "kcal"), do: "#{num_str(n)} cal"

  defp show_one(n, "m") do
    if n >= 1000 and fmod(n, 100) == 0, do: "#{num_str(n / 1000)} km", else: "#{num_str(n)} m"
  end

  defp show_one(n, "kg"), do: "#{num_str(n)} kg"
  defp show_one(n, "pct"), do: "#{num_str(n)}%"
  defp show_one(n, _reps), do: num_str(n)

  @doc "One value or range with its unit: \"10\", \"8–12\", \"60–70%\", \"1:00\", \"400 m\"."
  @spec show_entry(map() | nil, String.t()) :: String.t()
  def show_entry(nil, _unit), do: ""
  def show_entry(%{min: min, max: max}, unit) when min == max, do: show_one(min, unit)
  def show_entry(%{min: min, max: max}, "reps"), do: "#{num_str(min)}–#{num_str(max)}"

  def show_entry(%{min: min, max: max}, unit) do
    Regex.replace(~r/ ?(kg|cal|km|m|%|″)$/u, show_one(min, unit), "") <>
      "–" <> show_one(max, unit)
  end

  @doc "The dose as shown in set / round `i` (English words): \"10\", \"8–12/side\", \"max cal in 1:00\"."
  @spec show_dose_at(term(), non_neg_integer()) :: String.t()
  def show_dose_at(%{max: %{within: within}} = dose, _i) do
    unit = %{"kcal" => " cal", "m" => " m"}[dose.unit] || ""
    "max" <> unit <> if(within, do: " in #{clock(within)}", else: "")
  end

  def show_dose_at(%{} = dose, i) do
    case entry_at(dose, i) do
      nil -> ""
      e -> show_entry(e, dose.unit) <> if(dose.per_side, do: "/side", else: "")
    end
  end

  def show_dose_at(_dose, _i), do: ""

  # ── values per set / round ─────────────────────────────

  @doc "One cell value as typed (\"\" for missing cells, non-strings, junk)."
  @spec cell_text(term(), non_neg_integer(), String.t()) :: String.t()
  def cell_text(%{"cells" => cells}, i, key) when is_list(cells) do
    case Enum.at(cells, i) do
      %{} = cell ->
        case Map.get(cell, key) do
          value when is_binary(value) -> value
          _other -> ""
        end

      _other ->
        ""
    end
  end

  def cell_text(_row, _i, _key), do: ""

  @doc "A value relative to the column before: \"+5\", \"-0:05\", \"60→80\", \"60 ως 80\"."
  @spec relative?(term()) :: boolean()
  def relative?(text) do
    v = norm_text(text)

    Regex.match?(~r/^[+-]/, v) or
      Regex.match?(re("→|(?:^|\\s|[0-9])(?:ως|εως)(?:\\s|[0-9]|$)"), v)
  end

  @doc "Text measures (tempo) only repeat: an empty column is the one before."
  @spec repeat_text(term(), String.t(), non_neg_integer()) :: [String.t()]
  def repeat_text(row, key, n) do
    {values, _last} =
      Enum.map_reduce(range(n), "", fn i, last ->
        value =
          case String.trim(cell_text(row, i, key)) do
            "" -> last
            text -> text
          end

        {value, value}
      end)

    values
  end

  defp range(n) when is_integer(n) and n > 0, do: 0..(n - 1)
  defp range(_n), do: []

  defp load_unit(""), do: nil
  defp load_unit(nil), do: nil
  defp load_unit("%"), do: "%"
  defp load_unit(_kg), do: "kg"

  defp read_load_cell(raw) do
    token = read_load_cell_raw(raw)

    nums =
      case token do
        %{n: n} -> [n]
        %{a: a, b: b} -> [a, b]
        _other -> []
      end

    if Enum.any?(nums, &(abs(&1) > @max_number)),
      do: %{t: :words, text: String.trim(raw)},
      else: token
  end

  defp read_load_cell_raw(raw) do
    v = norm_load_text(raw)
    groups = fn m, i -> Enum.at(m, i, "") end

    cond do
      v == "" ->
        %{t: :empty}

      m = Regex.run(re("^([+-])#{@ln}#{@lu}$"), v) ->
        sign = if groups.(m, 1) == "-", do: -1, else: 1
        %{t: :delta, n: sign * to_num(groups.(m, 2)), unit: load_unit(groups.(m, 3))}

      m = Regex.run(re("^#{@ln}#{@lu}$"), v) ->
        %{t: :abs, n: to_num(groups.(m, 1)), unit: load_unit(groups.(m, 2))}

      m = Regex.run(re("^#{@ln}#{@lu}\\s*(?:\\+|↑)$"), v) ->
        %{t: :up, n: to_num(groups.(m, 1)), unit: load_unit(groups.(m, 2))}

      m = Regex.run(re("^#{@ln}#{@lu}\\s*(?:→|ως|εως)\\s*#{@ln}#{@lu}$"), v) ->
        pair_token(:spread, m, groups)

      (m = Regex.run(re("^#{@ln}#{@lu}\\s*-\\s*#{@ln}#{@lu}$"), v)) &&
          to_num(groups.(m, 1)) < to_num(groups.(m, 3)) ->
        pair_token(:range, m, groups)

      not_load_unit?(v) ->
        %{t: :wrong}

      true ->
        %{t: :words, text: String.trim(raw)}
    end
  end

  defp pair_token(t, m, groups) do
    a = load_unit(groups.(m, 2))
    b = load_unit(groups.(m, 4))

    if a && b && a != b,
      do: %{t: :wrong},
      else: %{t: t, a: to_num(groups.(m, 1)), b: to_num(groups.(m, 3)), unit: b || a}
  end

  @doc """
  Loads of one row over `n` columns, as the editor shows them:
  `%{values: [String.t()], errors: [code | nil], unit: \"kg\" | \"%\" | nil}`.
  The unit is written once per row; bare numbers, `+x`, `a→b` and `a-b`
  inherit it. Errors: `missing_unit`, `mixed_unit`, `wrong_unit`, `no_base`.
  """
  @spec set_loads(term(), non_neg_integer()) :: map()
  def set_loads(row, n) do
    %{columns: columns, unit: unit} = load_columns(row, n)

    %{
      values: Enum.map(columns, & &1.text),
      errors: Enum.map(columns, & &1.error),
      unit: unit
    }
  end

  @doc """
  The same loads as numbers, per column: `%{kind: :value, value, unit}`,
  `%{kind: :up, value, unit}` (builds up from there), `%{kind: :range, min, max, unit}`,
  `%{kind: :words, text}`, or nil (nothing, or a refused column). Also the
  row's unit and the last `+x` still running (`step`).
  """
  @spec set_load_readings(term(), non_neg_integer()) :: map()
  def set_load_readings(row, n) do
    %{columns: columns, unit: unit, step: step} = load_columns(row, n)
    %{readings: Enum.map(columns, & &1.reading), unit: unit, step: step}
  end

  defp load_columns(row, n) do
    tokens = Enum.map(range(n), &read_load_cell(cell_text(row, &1, "l")))
    unit = Enum.find_value(tokens, &Map.get(&1, :unit))
    fmt = fn v -> num_str(v) <> if(unit == "%", do: "%", else: " kg") end
    start = %{prev: nil, delta: nil, spread: nil, rising: false, last: nil, step: nil}

    {columns, state} =
      tokens
      |> Enum.with_index()
      |> Enum.map_reduce(start, fn {token, i}, state ->
        state = if token.t != :empty, do: %{state | rising: false}, else: state
        {column, state} = load_column(token, i, n, unit, fmt, state)
        {column, %{state | last: column}}
      end)

    %{columns: columns, unit: unit, step: state.delta}
  end

  defp column(text, reading, error \\ nil), do: %{text: text, reading: reading, error: error}

  defp load_column(%{t: :empty}, i, n, unit, fmt, state) do
    if state.rising and state.prev != nil and unit do
      {column("↑ " <> fmt.(state.prev), %{kind: :up, value: state.prev, unit: unit}), state}
    else
      prev =
        cond do
          state.spread -> spread_at(state.spread, i, n)
          state.delta != nil and state.prev != nil -> state.prev + state.delta
          true -> state.prev
        end

      state = %{state | prev: prev}

      cond do
        prev != nil and unit ->
          {column(fmt.(prev), %{kind: :value, value: round_to(prev, 100), unit: unit}), state}

        state.last ->
          {%{state.last | error: nil}, state}

        true ->
          {column("", nil), state}
      end
    end
  end

  defp load_column(%{t: :words, text: text}, _i, _n, _unit, _fmt, state),
    do: {column(text, %{kind: :words, text: text}), %{state | prev: nil, delta: nil, spread: nil}}

  defp load_column(%{t: :wrong}, _i, _n, _unit, _fmt, state),
    do: {column("", nil, "wrong_unit"), state}

  defp load_column(_token, _i, _n, nil, _fmt, state),
    do: {column("", nil, "missing_unit"), state}

  defp load_column(%{unit: stated}, _i, _n, unit, _fmt, state)
       when stated != nil and stated != unit,
       do: {column("", nil, "mixed_unit"), state}

  defp load_column(%{t: :delta}, _i, _n, _unit, _fmt, %{prev: nil} = state),
    do: {column("", nil, "no_base"), state}

  defp load_column(%{t: :delta, n: delta}, _i, _n, unit, fmt, state) do
    prev = state.prev + delta

    {column(fmt.(prev), %{kind: :value, value: round_to(prev, 100), unit: unit}),
     %{state | prev: prev, delta: delta, spread: nil}}
  end

  defp load_column(%{t: :spread, a: a, b: b}, i, _n, unit, fmt, state) do
    {column(fmt.(a), %{kind: :value, value: a, unit: unit}),
     %{state | prev: a, spread: %{a: a, b: b, i: i}, delta: nil}}
  end

  defp load_column(%{t: :up, n: value}, _i, _n, unit, fmt, state) do
    {column(fmt.(value), %{kind: :up, value: value, unit: unit}),
     %{state | prev: value, delta: nil, spread: nil, rising: true}}
  end

  defp load_column(%{t: :range, a: a, b: b}, _i, _n, unit, fmt, state) do
    {column(num_str(a) <> "–" <> fmt.(b), %{kind: :range, min: a, max: b, unit: unit}),
     %{state | prev: nil, delta: nil, spread: nil}}
  end

  defp load_column(%{t: :abs, n: value}, _i, _n, unit, fmt, state) do
    {column(fmt.(value), %{kind: :value, value: value, unit: unit}),
     %{state | prev: value, delta: nil, spread: nil}}
  end

  defp spread_at(%{a: a, b: b, i: from}, i, n),
    do: a + (b - a) * (i - from) / max(1, n - 1 - from)

  # ── measures per column ────────────────────────────────

  defp read_measure_cell(raw, clock?) do
    v = raw |> decimal_comma_norm() |> then(&Regex.replace(~r/^z(?:one)?\s*(?=[0-9])/, &1, ""))

    n =
      if clock?,
        do: "([0-9]+(?::[0-5][0-9])?(?:\\.[0-9]+)?)",
        else: "([0-9]+(?:\\.[0-9]+)?)"

    to_n = fn text ->
      if clock? and String.contains?(text, ":"),
        do: text |> String.split(":") |> Enum.reduce(0, fn x, acc -> acc * 60 + number(x) end),
        else: number(text)
    end

    cond do
      v == "" ->
        %{t: :empty}

      m = Regex.run(re("^([+-])#{n}$"), v) ->
        %{t: :delta, n: if(Enum.at(m, 1) == "-", do: -1, else: 1) * to_n.(Enum.at(m, 2))}

      m = Regex.run(re("^#{n}\\s*(?:→|ως|εως)\\s*#{n}(.*)$"), v) ->
        %{t: :spread, a: to_n.(Enum.at(m, 1)), b: to_n.(Enum.at(m, 2)), suffix: Enum.at(m, 3, "")}

      Regex.match?(re("^#{n}\\s*-\\s*#{n}(.*)$"), v) ->
        %{t: :text, text: String.trim(raw), numeric: true}

      m = Regex.run(re("^#{n}(.*)$"), v) ->
        %{t: :abs, n: to_n.(Enum.at(m, 1)), suffix: Enum.at(m, 2, "")}

      true ->
        %{t: :text, text: String.trim(raw), numeric: false}
    end
  end

  @doc """
  A numeric measure over `n` columns as the editor shows it: empty repeats
  (or keeps adding the last `+x`, or keeps spreading `a→b`), a range or text
  repeats as typed. With `clock?`, \"m:ss\" counts in seconds (pace, hold).
  """
  @spec progress(term(), String.t(), non_neg_integer(), boolean()) :: [String.t()]
  def progress(row, key, n, clock? \\ false),
    do: row |> measure_columns(key, n, clock?) |> Enum.map(& &1.text)

  @doc """
  The same measure as numbers per column: `%{value, suffix}` (the suffix as
  typed after the number, e.g. \"/km\", \" cm\"), `%{text}` for a range or
  words, or nil.
  """
  @spec progress_readings(term(), String.t(), non_neg_integer(), boolean()) :: [map() | nil]
  def progress_readings(row, key, n, clock? \\ false),
    do: row |> measure_columns(key, n, clock?) |> Enum.map(& &1.reading)

  defp measure_columns(row, key, n, clock?) do
    fmt = fn v ->
      if clock? and v >= 60,
        do: "#{trunc(Float.floor(v / 60))}:#{pad2(fmod(v, 60))}",
        else: js_string(round_to(v, 10))
    end

    start = %{prev: nil, delta: nil, spread: nil, suffix: "", last: nil}

    {columns, _state} =
      Enum.map_reduce(range(n), start, fn i, state ->
        raw = cell_text(row, i, key)
        {col, state} = measure_column(read_measure_cell(raw, clock?), raw, i, n, fmt, state)
        {col, %{state | last: col}}
      end)

    columns
  end

  defp measure_column(%{t: :empty}, _raw, i, n, fmt, state) do
    prev =
      cond do
        state.spread -> spread_at(state.spread, i, n)
        state.delta != nil and state.prev != nil -> state.prev + state.delta
        true -> state.prev
      end

    state = %{state | prev: prev}

    cond do
      prev != nil ->
        {column(fmt.(prev) <> state.suffix, %{value: prev, suffix: state.suffix}), state}

      state.last ->
        {state.last, state}

      true ->
        {column("", nil), state}
    end
  end

  defp measure_column(%{t: :delta, n: delta}, _raw, _i, _n, fmt, %{prev: prev} = state)
       when prev != nil do
    prev = prev + delta

    {column(fmt.(prev) <> state.suffix, %{value: prev, suffix: state.suffix}),
     %{state | prev: prev, delta: delta, spread: nil}}
  end

  defp measure_column(%{t: :spread, a: a, b: b, suffix: suffix}, _raw, i, _n, fmt, state) do
    {column(fmt.(a) <> suffix, %{value: a, suffix: suffix}),
     %{state | prev: a, spread: %{a: a, b: b, i: i}, delta: nil, suffix: suffix}}
  end

  defp measure_column(%{t: :abs, n: value, suffix: suffix}, raw, _i, _n, _fmt, state) do
    {column(String.trim(raw), %{value: value, suffix: suffix}),
     %{state | prev: value, suffix: suffix, delta: nil, spread: nil}}
  end

  defp measure_column(_text, raw, _i, _n, _fmt, state) do
    text = String.trim(raw)
    {column(text, %{text: text}), %{state | prev: nil, delta: nil, spread: nil}}
  end

  @doc "`no_base` per column for a change (\"+1\") with no number before it."
  @spec measure_cell_errors(term(), String.t(), non_neg_integer(), boolean()) :: [
          String.t() | nil
        ]
  def measure_cell_errors(row, key, n, clock? \\ false) do
    {errors, _base} =
      Enum.map_reduce(range(n), false, fn i, base ->
        case read_measure_cell(cell_text(row, i, key), clock?) do
          %{t: :empty} -> {nil, base}
          %{t: :delta} -> {if(base, do: nil, else: "no_base"), base}
          %{t: t} -> {nil, t in [:abs, :spread]}
        end
      end)

    errors
  end

  # ── tempo ──────────────────────────────────────────────

  @tempo ~r/^([0-9xχ])[-.\/ ]?([0-9xχ])[-.\/ ]?([0-9xχ])[-.\/ ]?([0-9xχ])$/u

  @doc "\"31X1\" → `%{down: 3, bottom: 1, up: \"X\", top: 1}`; anything else → nil."
  @spec tempo_parts(term()) :: map() | nil
  def tempo_parts(text) do
    case Regex.run(@tempo, norm_text(text)) do
      [_all, down, bottom, up, top] ->
        %{down: mark(down), bottom: mark(bottom), up: mark(up), top: mark(top)}

      nil ->
        nil
    end
  end

  defp mark(char) when char in ["x", "χ"], do: "X"
  defp mark(char), do: String.to_integer(char)

  @doc "The canonical tempo text (\"31X1\"), or nil."
  @spec tempo_canonical(term()) :: String.t() | nil
  def tempo_canonical(text) do
    case tempo_parts(text) do
      nil -> nil
      p -> "#{p.down}#{p.bottom}#{p.up}#{p.top}"
    end
  end
end
