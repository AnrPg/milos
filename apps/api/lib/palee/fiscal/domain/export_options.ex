defmodule Palee.Fiscal.Domain.ExportOptions do
  @moduledoc """
  Validation of accounting export options against a format's option list
  (ADR-245, `Fiscal.Ports.AccountingExportFormat`). Unknown keys are
  dropped, missing ones take their default; text is trimmed and at most
  120 characters, maps hold at most 40 entries of text up to 40
  characters.
  """

  @max_text 120
  @max_map 40
  @max_map_text 40

  @doc "`{:ok, options}` (string keys) or `{:error, {:invalid_fields, errors}}`."
  def normalize(specs, given) when is_map(given) do
    given = Map.new(given, fn {key, value} -> {to_string(key), value} end)

    {options, errors} =
      Enum.reduce(specs, {%{}, %{}}, fn spec, {options, errors} ->
        key = spec.key

        case value(spec, Map.get(given, key)) do
          {:ok, value} -> {Map.put(options, key, value), errors}
          {:error, reason} -> {options, Map.put(errors, "options.#{key}", reason)}
        end
      end)

    if errors == %{}, do: {:ok, options}, else: {:error, {:invalid_fields, errors}}
  end

  def normalize(_specs, _given), do: {:error, {:invalid_fields, %{"options" => :invalid}}}

  @doc "The defaults of an option list."
  def defaults(specs), do: Map.new(specs, &{&1.key, &1.default})

  @doc "Strips the internal parts of option specs for the API."
  def public(specs),
    do: Enum.map(specs, &Map.take(&1, [:key, :type, :default, :values, :description]))

  defp value(spec, nil), do: {:ok, spec.default}
  defp value(spec, ""), do: {:ok, spec.default}

  defp value(%{type: "string"} = spec, value) when is_binary(value) do
    value = String.trim(value)

    cond do
      String.length(value) > @max_text -> {:error, :too_long}
      Map.has_key?(spec, :format) and not Regex.match?(spec.format, value) -> {:error, :invalid}
      true -> {:ok, value}
    end
  end

  defp value(%{type: "integer"} = spec, value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> value(spec, number)
      _ -> {:error, :invalid}
    end
  end

  defp value(%{type: "integer"} = spec, value) when is_integer(value) do
    {min, max} = Map.get(spec, :range, {0, 999_999_999})
    if value >= min and value <= max, do: {:ok, value}, else: {:error, :out_of_range}
  end

  defp value(%{type: "boolean"}, value) when is_boolean(value), do: {:ok, value}
  defp value(%{type: "boolean"}, "true"), do: {:ok, true}
  defp value(%{type: "boolean"}, "false"), do: {:ok, false}

  defp value(%{type: "enum", values: values}, value) when is_binary(value) do
    if value in values, do: {:ok, value}, else: {:error, :invalid}
  end

  defp value(%{type: "map"} = spec, value) when is_map(value) do
    entries = Enum.map(value, fn {key, text} -> {to_string(key), text} end)

    cond do
      length(entries) > @max_map ->
        {:error, :too_many}

      Enum.all?(entries, fn {key, text} -> valid_map_entry?(spec, key, text) end) ->
        {:ok,
         entries
         |> Enum.reject(fn {_key, text} -> text in [nil, ""] end)
         |> Map.new(fn {key, text} -> {key, String.trim(to_string(text))} end)}

      true ->
        {:error, :invalid}
    end
  end

  defp value(_spec, _value), do: {:error, :invalid}

  defp valid_map_entry?(spec, key, text) do
    allowed_key? =
      case Map.get(spec, :keys) do
        nil -> String.length(key) in 1..@max_map_text
        keys -> key in keys
      end

    allowed_key? and
      (text in [nil, ""] or
         ((is_binary(text) or is_integer(text)) and
            String.length(to_string(text)) <= @max_map_text))
  end
end
