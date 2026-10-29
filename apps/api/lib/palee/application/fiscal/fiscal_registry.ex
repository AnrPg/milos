defmodule Palee.Application.Fiscal.FiscalRegistry do
  @moduledoc """
  Staff › billing details › «Συμπλήρωση από το ΑΦΜ» (ADR-265): the
  business's AADE registry connection and the look-up of a Greek business
  by ΑΦΜ, used for the business's own details (mockup s1) and for an
  invoice buyer. The look-up's date is the gym's local date (ADR-176).
  """

  alias Palee.Organizations
  alias Palee.Fiscal.Registry

  @doc "`%{connection: connection | nil}`."
  def connection(context), do: %{connection: Registry.connection(context)}

  def save_connection(context, params, now \\ DateTime.utc_now()) do
    params = atomize(params, ~w(environment username password)a)

    with {:ok, connection} <-
           Registry.save_connection(context, params, Map.get(context, :user_id), now) do
      {:ok, %{connection: connection}}
    end
  end

  @doc "`{:ok, %{business: business}}` or `{:error, reason}` (see `Fiscal.Registry.lookup/3`)."
  def lookup(context, tax_id, now \\ DateTime.utc_now()) do
    with {:ok, business} <-
           Registry.lookup(context, tax_id, Organizations.local_date(context, now)) do
      {:ok, %{business: business}}
    end
  end

  defp atomize(params, keys) when is_map(params) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Map.get(params, key, Map.get(params, Atom.to_string(key))) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp atomize(_params, _keys), do: %{}
end
