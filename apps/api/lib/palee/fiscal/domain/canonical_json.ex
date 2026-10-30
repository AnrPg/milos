defmodule Palee.Fiscal.Domain.CanonicalJson do
  @moduledoc """
  Canonical JSON for hashing and signing fiscal records (ADR-242).

  Object keys are sorted by their UTF-8 bytes, there is no insignificant
  whitespace, and only `null`, booleans, integers, strings, lists and maps
  are accepted: money is integer minor units, rates are basis points and
  times are ISO 8601 strings, so no float ever reaches a hash. Atoms become
  strings; `Date`/`DateTime` become ISO 8601. The same term always gives the
  same bytes, on any machine.
  """

  @doc "Encodes `term` canonically; raises `ArgumentError` on floats and other terms."
  def encode!(term), do: term |> do_encode() |> IO.iodata_to_binary()

  @doc "`{:ok, binary}` or `{:error, :not_canonical}`."
  def encode(term) do
    {:ok, encode!(term)}
  rescue
    ArgumentError -> {:error, :not_canonical}
  end

  @doc "The term with atoms, dates and keys normalised as `encode!/1` sees it."
  def normalize(term), do: term |> encode!() |> Jason.decode!()

  defp do_encode(nil), do: "null"
  defp do_encode(true), do: "true"
  defp do_encode(false), do: "false"
  defp do_encode(value) when is_integer(value), do: Integer.to_string(value)
  defp do_encode(value) when is_binary(value), do: string(value)
  defp do_encode(%DateTime{} = value), do: value |> DateTime.to_iso8601() |> string()
  defp do_encode(%Date{} = value), do: value |> Date.to_iso8601() |> string()
  defp do_encode(value) when is_atom(value), do: value |> Atom.to_string() |> string()

  defp do_encode(value) when is_list(value),
    do: ["[", value |> Enum.map(&do_encode/1) |> Enum.intersperse(","), "]"]

  defp do_encode(value) when is_map(value) and not is_struct(value) do
    pairs =
      value
      |> Enum.map(fn {key, item} -> {key_string(key), item} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> ensure_unique_keys()
      |> Enum.map(fn {key, item} -> [string(key), ":", do_encode(item)] end)
      |> Enum.intersperse(",")

    ["{", pairs, "}"]
  end

  defp do_encode(value),
    do: raise(ArgumentError, "not canonical JSON: #{inspect(value, limit: 3)}")

  defp key_string(key) when is_binary(key), do: key
  defp key_string(key) when is_atom(key) and not is_nil(key), do: Atom.to_string(key)
  defp key_string(key), do: raise(ArgumentError, "not a JSON key: #{inspect(key)}")

  defp ensure_unique_keys(pairs) do
    keys = Enum.map(pairs, &elem(&1, 0))

    if length(Enum.uniq(keys)) == length(keys),
      do: pairs,
      else: raise(ArgumentError, "duplicate JSON keys")
  end

  # Jason escapes control characters, quotes and backslashes the RFC 8259 way
  # and leaves other UTF-8 as is.
  defp string(value) do
    if String.valid?(value),
      do: Jason.encode!(value),
      else: raise(ArgumentError, "not UTF-8")
  end
end
