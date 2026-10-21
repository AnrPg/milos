defmodule Palee.Identity.Domain.FilterFields do
  @moduledoc """
  Field parsers shared by the typed, versioned list filters (ADR-151):
  Ημερολόγιο, Vault and Πρόοδος (ADR-162). Every parser takes the raw value
  (JSON or a query string, so a list may also be a comma-separated string)
  and answers `{:ok, value}` or `{:error, [{field, message}]}`.
  """

  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
  @source_words ~w(freeform device)
  @max_sources 20

  @doc "String keys, whatever the caller passed."
  def stringify(params) when is_map(params),
    do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  def version(nil, _version), do: :ok
  def version(version, version), do: :ok

  def version(value, version) when is_binary(value) do
    if value == Integer.to_string(version), do: :ok, else: version(:unsupported, version)
  end

  def version(_other, _version), do: {:error, [v: "is not a supported filter version"]}

  @doc "A list from a JSON list or a comma-separated string."
  def list(nil), do: {:ok, []}
  def list(""), do: {:ok, []}
  def list(value) when is_binary(value), do: {:ok, String.split(value, ",", trim: true)}
  def list(value) when is_list(value), do: {:ok, value}
  def list(_value), do: :error

  @doc "A subset of `allowed`, unique, in the allowed list's order."
  def subset(field, value, allowed) do
    case list(value) do
      {:ok, values} ->
        if Enum.all?(values, &(is_binary(&1) and &1 in allowed)),
          do: {:ok, Enum.filter(allowed, &(&1 in values))},
          else: {:error, [{field, "has an unknown value"}]}

      :error ->
        {:error, [{field, "must be a list"}]}
    end
  end

  @doc "Source tokens: provider ids, `freeform`, `device` (sorted, unique)."
  def sources(field, value) do
    case list(value) do
      {:ok, values} ->
        values = values |> Enum.map(&source/1) |> Enum.uniq()

        cond do
          Enum.any?(values, &is_nil/1) -> {:error, [{field, "has an unknown source"}]}
          length(values) > @max_sources -> {:error, [{field, "at most #{@max_sources}"}]}
          true -> {:ok, Enum.sort(values)}
        end

      :error ->
        {:error, [{field, "must be a list"}]}
    end
  end

  defp source(value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()
    if value in @source_words or value =~ @uuid, do: value
  end

  defp source(_value), do: nil

  @doc "An optional ISO date."
  def date(_field, nil), do: {:ok, nil}
  def date(_field, ""), do: {:ok, nil}
  def date(_field, %Date{} = date), do: {:ok, date}

  def date(field, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, [{field, "must be a date (YYYY-MM-DD)"}]}
    end
  end

  def date(field, _value), do: {:error, [{field, "must be a date (YYYY-MM-DD)"}]}

  @doc "An optional `from..to` date range, `to` not before `from`."
  def date_range(from, to) do
    with {:ok, from} <- date(:date_from, from),
         {:ok, to} <- date(:date_to, to) do
      if from && to && Date.compare(to, from) == :lt,
        do: {:error, [date_to: "must not be before date_from"]},
        else: {:ok, {from, to}}
    end
  end

  @doc "Optional free text, trimmed and collapsed, `min..max` characters."
  def text(_field, nil, _min, _max), do: {:ok, nil}

  def text(field, value, min, max) when is_binary(value) do
    value = value |> String.split() |> Enum.join(" ")

    cond do
      value == "" -> {:ok, nil}
      String.length(value) < min -> {:error, [{field, "at least #{min} characters"}]}
      String.length(value) > max -> {:error, [{field, "at most #{max} characters"}]}
      true -> {:ok, value}
    end
  end

  def text(field, _value, _min, _max), do: {:error, [{field, "must be text"}]}

  @doc "A date as ISO text, or nil."
  def iso(nil), do: nil
  def iso(%Date{} = date), do: Date.to_iso8601(date)
end
