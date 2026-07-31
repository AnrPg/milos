defmodule MilosTraining.Workouts.Domain.WorkoutDsl.Values do
  @moduledoc false

  def duration(raw) when is_binary(raw) do
    value = raw |> String.trim() |> String.downcase()

    regex =
      ~r/(\d+(?:\.\d+)?)\s*(hours?|hour|hrs?|hr|h|minutes?|minute|mins?|min|m|seconds?|second|secs?|sec|s)/i

    matches = Regex.scan(regex, value)

    remainder =
      value
      |> String.replace(regex, "")
      |> String.replace(~r/\s+/, "")

    if matches == [] or remainder != "" do
      :error
    else
      seconds =
        Enum.reduce(matches, 0.0, fn [_, raw_number, unit], total ->
          with {number, ""} <- Float.parse(raw_number) do
            multiplier =
              cond do
                String.starts_with?(unit, "h") -> 3_600
                String.starts_with?(unit, "m") -> 60
                true -> 1
              end

            total + number * multiplier
          else
            _ -> total
          end
        end)

      if seconds > 0, do: {:ok, round(seconds)}, else: :error
    end
  end

  def duration(_value), do: :error

  def duration_range(raw) when is_binary(raw) do
    case String.split(raw, ~r/\s*(?:\.\.|to)\s*/i, parts: 2) do
      [left, right] ->
        with {:ok, minimum} <- duration(left),
             {:ok, maximum} <- duration(right),
             true <- maximum >= minimum do
          {:ok, [minimum, maximum]}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def distance(raw) when is_binary(raw) do
    case Regex.run(
           ~r/^(\d+(?:\.\d+)?)\s*(m|meter|meters|km|kilometer|kilometers)$/i,
           String.trim(raw)
         ) do
      [_, raw_number, unit] ->
        with {number, ""} <- Float.parse(raw_number) do
          multiplier = if String.starts_with?(String.downcase(unit), "k"), do: 1_000, else: 1
          {:ok, normalize_number(number * multiplier)}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def distance(_value), do: :error

  def load(raw, opts \\ [])

  def load(raw, opts) when is_binary(raw) do
    normalized = raw |> String.trim() |> String.downcase()
    signed? = Keyword.get(opts, :signed, false)
    sign = if signed?, do: "[+-]?", else: ""
    regex = Regex.compile!("^(#{sign}\\d+(?:\\.\\d+)?)\\s*(kg|lb|%1rm|%|bw)$", "i")

    case {normalized, Regex.run(regex, String.trim(raw))} do
      {"bw", _match} ->
        {:ok, %{value: 0, mode: "bw", unit: "bodyweight"}}

      {_normalized, [_, raw_number, raw_unit]} ->
        unit = String.downcase(raw_unit)

        if unit == "bw" do
          {:ok, %{value: 0, mode: "bw", unit: "bodyweight"}}
        else
          with {number, ""} <- Float.parse(raw_number) do
            mode = if unit in ["%1rm", "%"], do: "pct_1rm", else: "absolute"
            load_unit = if mode == "pct_1rm", do: "pct_1rm", else: unit
            {:ok, %{value: normalize_number(number), mode: mode, unit: load_unit}}
          else
            _ -> :error
          end
        end

      {_normalized, _match} ->
        :error
    end
  end

  def load(_value, _opts), do: :error

  def load_range(raw) when is_binary(raw) do
    case String.split(raw, ~r/\s*(?:->|→)\s*/, parts: 2) do
      [left, right] ->
        with {:ok, start_load} <- load(left),
             {:ok, end_load} <- load(right),
             true <- start_load.mode == end_load.mode,
             true <- start_load.unit == end_load.unit do
          {:ok, start_load, end_load}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def load_range(_value), do: :error

  def integer(raw, opts \\ [])

  def integer(raw, opts) when is_binary(raw) do
    minimum = Keyword.get(opts, :minimum, 1)

    case Integer.parse(String.trim(raw)) do
      {number, ""} when number >= minimum -> {:ok, number}
      _ -> :error
    end
  end

  def integer(_value, _opts), do: :error

  def number(raw, opts \\ [])

  def number(raw, opts) when is_binary(raw) do
    minimum = Keyword.get(opts, :minimum, 0)
    maximum = Keyword.get(opts, :maximum, :infinity)

    case Float.parse(String.trim(raw)) do
      {number, ""} when number >= minimum and (maximum == :infinity or number <= maximum) ->
        {:ok, normalize_number(number)}

      _ ->
        :error
    end
  end

  def number(_value, _opts), do: :error

  def boolean(raw) when is_binary(raw) do
    case String.downcase(String.trim(raw)) do
      value when value in ["true", "yes", "on"] -> {:ok, true}
      value when value in ["false", "no", "off"] -> {:ok, false}
      _ -> :error
    end
  end

  def boolean(_value), do: :error

  def list(raw) when is_binary(raw) do
    values =
      raw
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if values == [], do: :error, else: {:ok, Enum.uniq(values)}
  end

  def list(_value), do: :error

  def slug(raw) when is_binary(raw) do
    value = raw |> String.trim() |> String.downcase()
    if Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, value), do: {:ok, value}, else: :error
  end

  def slug(_value), do: :error

  def normalize_number(number) when is_float(number) and trunc(number) == number,
    do: trunc(number)

  def normalize_number(number), do: number

  def format_duration(seconds) when is_integer(seconds) and seconds > 0 do
    hours = div(seconds, 3_600)
    minutes = div(rem(seconds, 3_600), 60)
    remaining_seconds = rem(seconds, 60)

    [
      if(hours > 0, do: "#{hours} hr"),
      if(minutes > 0, do: "#{minutes} min"),
      if(remaining_seconds > 0, do: "#{remaining_seconds} sec")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def format_duration(seconds), do: to_string(seconds)

  def format_distance(meters) when is_number(meters) and meters >= 1_000 do
    kilometers = meters / 1_000
    "#{format_number(kilometers)} km"
  end

  def format_distance(meters), do: "#{format_number(meters)} m"

  def format_load(value, "pct_1rm", _unit), do: "#{format_number(value)} %1rm"
  def format_load(_value, "bw", _unit), do: "bw"
  def format_load(value, _mode, unit), do: "#{format_number(value)} #{unit || "kg"}"

  def format_number(number) when is_integer(number), do: Integer.to_string(number)

  def format_number(number) when is_float(number),
    do:
      :erlang.float_to_binary(number, decimals: 2)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")

  def format_number(number), do: to_string(number)
end
