defmodule Palee.Application.GetFinanceReconciliationCandidates do
  @moduledoc """
  Ranked internal payment/reversal facts that could match a statement line
  (ADR-126), each with its evaluation and the member's display name for the
  admin matching screen.
  """

  alias Palee.{Finance, Identity}

  def call(%{organization_id: organization_id} = context, record_id)
      when is_binary(organization_id) do
    with {:ok, %{record: record, candidates: candidates}} <-
           Finance.reconciliation_candidates(context, record_id) do
      names = member_names(candidates)

      {:ok,
       %{
         reconciliation_record: record,
         candidates:
           Enum.map(candidates, fn candidate ->
             %{
               target_type: Atom.to_string(candidate.kind),
               target_id: candidate.id,
               amount_cents: candidate.amount_cents,
               currency: candidate.currency,
               occurred_on: candidate.occurred_on,
               status: candidate.status,
               payment_method: candidate.payment_method,
               invoice_number: candidate.invoice_number,
               member_user_id: candidate.user_id,
               member_name: Map.get(names, candidate.user_id),
               evaluation: candidate.evaluation
             }
           end)
       }}
    end
  end

  def call(_context, _record_id), do: {:error, :organization_context_required}

  defp member_names(candidates) do
    candidates
    |> Enum.map(& &1.user_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(fn user -> {user.id, Map.get(user, :display_nickname) || user.nickname} end)
  end
end
