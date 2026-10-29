defmodule Palee.Application.Fiscal.FiscalTaxSettings do
  @moduledoc """
  Staff › Fiscal › taxes and accounting exports (ADR-244, ADR-245): the
  tax categories the gym may give what it sells, its US sales tax rates,
  the accounting export formats with the gym's options, and the exports
  themselves (fiscal documents plus Finance payments of the period).
  """

  alias Palee.Finance
  alias Palee.Fiscal.{Exports, Taxes}

  @max_export_days 366

  @doc "`%{country, categories, default, max_exemption_reason}`."
  def categories(context),
    do: context |> Taxes.categories() |> Map.put(:max_exemption_reason, Taxes.max_exemption_reason())

  @doc "`%{applies, rates, states}`."
  def sales_tax_rates(context), do: Taxes.sales_tax_rates(context)

  @doc "Replaces the US sales tax rate table (`params[\"rates\"]`)."
  def save_sales_tax_rates(context, params, now \\ DateTime.utc_now()) do
    rates = Map.get(params, "rates") || Map.get(params, :rates) || []
    Taxes.save_sales_tax_rates(context, rates, Map.get(context, :user_id), now)
  end

  @doc "`%{formats, settings}`."
  def export_formats(context),
    do: %{formats: Exports.formats(), settings: Exports.settings(context)}

  @doc "Saves the gym's options of one format (`params[\"options\"]`)."
  def save_export_settings(context, format, params, now \\ DateTime.utc_now()) do
    options = Map.get(params, "options") || Map.get(params, :options) || %{}

    Exports.save_settings(context, format, options, Map.get(context, :user_id), now)
  end

  @doc """
  The export of `params` `from`..`to` (at most #{@max_export_days} days) in
  `format`. `{:ok, %{filename, content, content_type, documents, payments,
  skipped}}` or `{:error, reason}`.
  """
  def export(context, format, params, now \\ DateTime.utc_now()) do
    with {:ok, _module} <- Exports.format(format),
         {:ok, from, to} <- range(params) do
      payments =
        context
        |> Finance.accounting_export_rows(from, to)
        |> Map.get("payments", [])

      Exports.export(context, format, from, to, %{}, payments, Map.get(context, :user_id), now)
    end
  end

  defp range(params) do
    with {:ok, from} <- date(param(params, :from)),
         {:ok, to} <- date(param(params, :to)),
         true <-
           (Date.compare(from, to) != :gt and Date.diff(to, from) < @max_export_days) ||
             {:error, :invalid_date_range} do
      {:ok, from, to}
    end
  end

  defp param(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp date(%Date{} = date), do: {:ok, date}

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date_range}
    end
  end

  defp date(_value), do: {:error, :invalid_date_range}
end
