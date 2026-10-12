defmodule MilosTraining.Application.ListFinanceRefundReceipts do
  @moduledoc """
  Lists refund receipts (ADR-116). Staff see the tenant's receipts (with
  optional `user_id`, `q`, `from`, `to`, `limit` filters); a member sees only
  their own, whatever filters they send.
  """

  alias MilosTraining.Finance

  def call(%{organization_id: organization_id} = context, viewer, params)
      when is_binary(organization_id) do
    filters =
      case viewer do
        :staff -> params || %{}
        {:member, user_id} when is_binary(user_id) -> %{"user_id" => user_id}
      end

    receipts =
      context
      |> Finance.list_refund_receipts(filters)
      |> Enum.map(&Map.drop(&1, [:snapshot]))

    {:ok, %{refund_receipts: receipts}}
  end

  def call(_context, _viewer, _params), do: {:error, :organization_context_required}
end
