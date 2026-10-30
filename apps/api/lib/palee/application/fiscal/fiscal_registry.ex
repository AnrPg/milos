defmodule Palee.Application.Fiscal.FiscalRegistry do
  @moduledoc """
  Staff › billing details › «Συμπλήρωση από το ΑΦΜ» (ADR-265): the
  business's AADE registry connection and the look-up of a Greek business
  by ΑΦΜ, used for the business's own details (mockup s1) and for an
  invoice buyer. The look-up's date is the gym's local date (ADR-176).
  """

  alias Palee.Organizations
  alias Palee.Application.Fiscal.FiscalConnections
  alias Palee.Fiscal.Registry

  @doc "`%{connection: connection | nil}`."
  def connection(context), do: %{connection: Registry.connection(context)}

  @doc """
  Saves the registry connection, then checks it with a look-up of the
  business's own ΑΦΜ (ADR-273): `{:ok, %{connection, check}}`.
  """
  def save_connection(context, params, now \\ DateTime.utc_now(), opts \\ []) do
    params =
      params
      |> atomize(~w(environment username password)a)
      |> Map.put(:updated_by_platform, Keyword.get(opts, :platform) == true)

    with :ok <- FiscalConnections.guard(context, opts),
         {:ok, _connection} <-
           Registry.save_connection(context, params, Map.get(context, :user_id), now) do
      {:ok, FiscalConnections.after_save(context, "registry", now)}
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
