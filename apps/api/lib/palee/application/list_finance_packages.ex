defmodule Palee.Application.ListFinancePackages do
  alias Palee.Application.{BranchReport, PackageBranches}
  alias Palee.Application.Payments.OnlineSales
  alias Palee.Finance

  def call, do: {:ok, %{packages: Finance.list_packages()}}

  @doc """
  ADR-186 §8: branch staff see the packages valid at one of their branches.
  With `location_ids` (§7) only the packages valid at one of the chosen
  branches, or everywhere, stay.
  """
  def call(context, params \\ %{}) do
    report = BranchReport.resolve_list(context, params)

    packages =
      context
      |> PackageBranches.visible(Finance.list_packages(context))
      |> BranchReport.covering_only(report, &PackageBranches.target/1)
      |> then(&OnlineSales.with_visibility(context, &1))

    {:ok, %{packages: packages, branch_filter: BranchReport.filter_payload(report)}}
  end
end
