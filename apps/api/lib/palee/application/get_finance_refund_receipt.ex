defmodule Palee.Application.GetFinanceRefundReceipt do
  @moduledoc """
  Reads one refund receipt (ADR-126) for `:staff` or for `{:member, user_id}`.
  A member asking for someone else's receipt gets `:not_found`, so receipt
  ids cannot be probed.
  """

  alias Palee.Finance

  def call(%{organization_id: organization_id} = context, id, viewer)
      when is_binary(organization_id) do
    case {Finance.get_refund_receipt(context, id), viewer} do
      {nil, _viewer} -> {:error, :not_found}
      {receipt, :staff} -> {:ok, receipt}
      {%{user_id: user_id} = receipt, {:member, user_id}} -> {:ok, receipt}
      {_receipt, _viewer} -> {:error, :not_found}
    end
  end

  def call(_context, _id, _viewer), do: {:error, :organization_context_required}
end
