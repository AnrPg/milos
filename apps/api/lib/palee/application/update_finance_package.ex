defmodule Palee.Application.UpdateFinancePackage do
  alias Palee.Application.Fiscal.SoldItemTax
  alias Palee.Application.PackageBranches
  alias Palee.Application.Payments.OnlineSales
  alias Palee.Finance

  def call(id, params), do: Finance.update_package(id, params)

  @doc """
  ADR-186 §8: only a package valid inside the acting branches changes.
  ADR-271: a `sold_online` sent by staff is the owner's choice.
  """
  def call(context, id, params, now \\ DateTime.utc_now()) do
    with :ok <- SoldItemTax.check(context, params),
         :ok <- PackageBranches.authorize_change(context, id, params),
         {:ok, package} <-
           Finance.update_package(context, id, OnlineSales.owner_choice(params, now)) do
      {:ok, OnlineSales.with_visibility(context, package)}
    end
  end
end
