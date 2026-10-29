defmodule Palee.Application.Fiscal.SoldItemTax do
  @moduledoc """
  ADR-244: the tax category of a package, product or variant being saved
  must be one the business's country offers. Finance and Shop use cases call
  `check/2` with the request params before they save; the column checks
  (known category, reason with `exempt`) stay in the changesets.
  """

  alias Palee.Fiscal.Taxes

  @doc """
  `:ok` when `params` name no `tax_category` or one the country offers,
  else `{:error, {:invalid_fields, errors}}`. `params` may be a list (the
  variants of a product): every entry is checked.
  """
  def check(context, params) when is_list(params) do
    Enum.reduce_while(params, :ok, fn entry, :ok ->
      case check(context, entry) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def check(context, params) when is_map(params) do
    case fetch(params, :tax_category) do
      {:ok, category} when is_binary(category) and category != "" ->
        Taxes.check_category(context, category, value(params, :exemption_reason))

      _none ->
        :ok
    end
  end

  def check(_context, _params), do: :ok

  defp fetch(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(params, Atom.to_string(key))
    end
  end

  defp value(params, key) do
    case fetch(params, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end
end
