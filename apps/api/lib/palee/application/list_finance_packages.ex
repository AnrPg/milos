defmodule Palee.Application.ListFinancePackages do
  alias Palee.Application.PackageBranches
  alias Palee.Finance

  def call, do: {:ok, %{packages: Finance.list_packages()}}

  @doc "ADR-186 §8: branch staff see the packages valid at one of their branches."
  def call(context),
    do: {:ok, %{packages: PackageBranches.visible(context, Finance.list_packages(context))}}
end
