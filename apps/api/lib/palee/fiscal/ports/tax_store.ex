defmodule Palee.Fiscal.Ports.TaxStore do
  @moduledoc """
  Persistence of the gym's tax and accounting-export settings (ADR-244,
  ADR-245): US sales tax rates by state and ZIP code, and the options of
  each accounting export format. It also reads document lines in bulk for
  exports. Every callback takes the tenant context first; the facade
  (`Palee.Fiscal.TaxStore`) opens the tenant session.
  """

  @type context :: map()
  @type result(value) :: {:ok, value} | {:error, term()}

  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) :: result(term())

  @doc "Rates as `%{state, zip, rate_bp, label}`, by state then ZIP (state-wide first)."
  @callback list_sales_tax_rates(context()) :: [map()]
  @doc "Replaces the whole rate table."
  @callback replace_sales_tax_rates(context(), [map()], actor_id :: binary() | nil) ::
              result([map()])

  @callback list_export_settings(context()) :: [map()]
  @callback get_export_setting(context(), format :: String.t()) :: map() | nil
  @callback save_export_setting(context(), String.t(), map(), actor_id :: binary() | nil) ::
              result(map())

  @doc "The lines of the given documents, by document id, in position order."
  @callback lines_for_documents(context(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => [map()]}
end
