defmodule Palee.Application.CreateFinancePackage do
  alias Palee.Application.PackageBranches
  alias Palee.Finance

  def call(params), do: Finance.create_package(params)

  @doc "ADR-186 §8: a branch manager's package is valid at their branches only."
  def call(context, params) do
    with {:ok, params} <- PackageBranches.for_create(context, params),
         do: Finance.create_package(context, params)
  end
end
