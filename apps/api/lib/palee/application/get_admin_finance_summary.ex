defmodule Palee.Application.GetAdminFinanceSummary do
  @moduledoc """
  The finance page summary. ADR-186 §7: `location_ids` filters it to some
  branches (inside the person's scope), and `branches` splits the headline
  figures per branch when the person sees two or more.
  """

  alias Palee.Application.BranchReport
  alias Palee.Finance

  def call, do: {:ok, Finance.financial_summary()}

  def call(context, params) do
    params = stringify(params)
    report = BranchReport.resolve(context, params)
    summary = Finance.financial_summary(context, BranchReport.scope_params(params, report))

    branches =
      BranchReport.splits(context, report, fn users, _location_id ->
        totals = Finance.financial_summary(context, Map.put(params, "user_ids", users)).totals

        %{
          active_memberships: totals.active_memberships,
          paid_revenue_cents: totals.paid_revenue_cents,
          outstanding_invoice_balance_cents: totals.outstanding_invoice_balance_cents
        }
      end)

    {:ok,
     summary
     |> Map.put(:branch_filter, BranchReport.filter_payload(report))
     |> Map.put(:branches, branches)}
  end

  defp stringify(params) when is_map(params),
    do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp stringify(_params), do: %{}
end
