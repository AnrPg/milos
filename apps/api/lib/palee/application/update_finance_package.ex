defmodule Palee.Application.UpdateFinancePackage do
  alias Palee.Application.Fiscal.SoldItemTax
  alias Palee.Application.PackageBranches
  alias Palee.Finance

  def call(id, params), do: Finance.update_package(id, params)

  @doc "ADR-186 §8: only a package valid inside the acting branches changes."
  def call(context, id, params) do
    with :ok <- SoldItemTax.check(context, params),
         :ok <- PackageBranches.authorize_change(context, id, params),
         do: Finance.update_package(context, id, params)
  end
end
