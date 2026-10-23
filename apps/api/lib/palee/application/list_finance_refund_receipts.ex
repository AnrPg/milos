defmodule Palee.Application.ListFinanceRefundReceipts do
  @moduledoc """
  Lists refund receipts (ADR-126). Staff see the tenant's receipts (with
  optional `user_id`, `q`, `from`, `to`, `limit` filters); a member sees only
  their own, whatever filters they send.

  ADR-186 §7: staff who name `location_ids` see the receipts of the people
  whose home branch is in the filter; the response then echoes
  `branch_filter`.
  """

  alias Palee.Application.BranchReport
  alias Palee.Finance

  def call(%{organization_id: organization_id} = context, :staff, params)
      when is_binary(organization_id) do
    params = params || %{}
    report = BranchReport.resolve_list(context, params)

    filters =
      params
      |> Map.drop(["location_ids", :location_ids])
      |> then(&if(report.filter == :all, do: &1, else: Map.put(&1, "user_ids", report.user_ids)))

    {:ok,
     %{
       refund_receipts: receipts(context, filters),
       branch_filter: BranchReport.filter_payload(report)
     }}
  end

  def call(%{organization_id: organization_id} = context, {:member, user_id}, _params)
      when is_binary(organization_id) and is_binary(user_id),
      do: {:ok, %{refund_receipts: receipts(context, %{"user_id" => user_id})}}

  def call(_context, _viewer, _params), do: {:error, :organization_context_required}

  defp receipts(context, filters) do
    context
    |> Finance.list_refund_receipts(filters)
    |> Enum.map(&Map.drop(&1, [:snapshot]))
  end
end
