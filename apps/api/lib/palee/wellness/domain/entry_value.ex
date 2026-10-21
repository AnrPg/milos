defmodule Palee.Wellness.Domain.EntryValue do
  @moduledoc """
  One kind of wellness entry (ADR-159 §1). A kind validates and normalises its
  own `value` map (string keys, as stored in `jsonb`) and may say which
  instant the entry counts at: a night counts on the morning you wake up.
  Adding a kind is a module and a line in `EntryKinds`, plus the kind in the
  table's check constraint.
  """

  @type errors :: %{optional(String.t()) => String.t()}

  @callback cast(map()) :: {:ok, map()} | {:error, errors()}
  @callback counts_at(value :: map(), occurred_at :: DateTime.t()) :: DateTime.t()

  @doc "Reads a key given as a string or an atom."
  def get(params, key) when is_map(params) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(params, fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
    end
  end

  @doc "An optional integer in `min..max`; `nil` stays `nil`."
  def integer(params, key, min, max) do
    case get(params, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value >= min and value <= max -> {:ok, value}
      _value -> {:error, %{key => "must be a whole number from #{min} to #{max}"}}
    end
  end

  @doc "An optional value from `allowed`."
  def one_of(params, key, allowed) do
    case get(params, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if value in allowed, do: {:ok, value}, else: invalid(key, allowed)

      _value ->
        invalid(key, allowed)
    end
  end

  @doc "Optional trimmed text of at most `max` characters (blank is `nil`)."
  def text(params, key, max) do
    case get(params, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case String.trim(value) do
          "" ->
            {:ok, nil}

          trimmed ->
            if String.length(trimmed) <= max,
              do: {:ok, trimmed},
              else: {:error, %{key => "is too long"}}
        end

      _value ->
        {:error, %{key => "must be text"}}
    end
  end

  @doc "An optional ISO-8601 instant, normalised to UTC."
  def instant(params, key) do
    case get(params, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, at, _offset} -> {:ok, DateTime.shift_zone!(at, "Etc/UTC")}
          {:error, _reason} -> {:error, %{key => "must be an ISO-8601 date-time"}}
        end

      %DateTime{} = at ->
        {:ok, DateTime.shift_zone!(at, "Etc/UTC")}

      _value ->
        {:error, %{key => "must be an ISO-8601 date-time"}}
    end
  end

  @doc "Collects `{field, result}` pairs into one value map or every error."
  def collect(results) do
    Enum.reduce(results, {%{}, %{}}, fn
      {_key, {:ok, nil}}, acc -> acc
      {key, {:ok, value}}, {values, errors} -> {Map.put(values, key, value), errors}
      {_key, {:error, error}}, {values, errors} -> {values, Map.merge(errors, error)}
    end)
    |> case do
      {values, errors} when errors == %{} -> {:ok, values}
      {_values, errors} -> {:error, errors}
    end
  end

  defp invalid(key, allowed),
    do: {:error, %{key => "must be one of: #{Enum.join(allowed, ", ")}"}}
end
