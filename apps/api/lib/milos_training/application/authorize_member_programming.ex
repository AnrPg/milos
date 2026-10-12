defmodule MilosTraining.Application.AuthorizeMemberProgramming do
  @moduledoc """
  ADR-115: personal programming for gym members requires an explicit package
  grant.

  A member's role does not imply personal programming, so each member's
  effective Finance contract must include the `personal_programming` channel
  and the `execute_assigned_workouts` capability. The check is independent of
  the tenant's ADR-040 rollout mode (`EntitlementPolicy.authorize_explicit/2`)
  and runs before any library copy or assignment write. Athletes are not
  checked here; they keep the rollout-governed touchpoint reservation.
  """

  alias MilosTraining.{Finance, Identity}
  alias MilosTraining.Finance.Domain.EntitlementPolicy

  @request %{channel: :personal_programming, capability: :execute_assigned_workouts}

  def call(_context, []), do: :ok

  def call(%{organization_id: organization_id} = context, member_ids)
      when is_binary(organization_id) and is_list(member_ids) do
    Enum.reduce_while(member_ids, :ok, fn member_id, :ok ->
      entitlement = Finance.get_effective_entitlement(context, member_id)

      case EntitlementPolicy.authorize_explicit(entitlement, @request) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, denial(member_id, reason)}
      end
    end)
  end

  def call(_context, _member_ids), do: {:error, :organization_context_required}

  defp denial(member_id, reason) do
    nickname =
      case Identity.find_by_id(member_id) do
        %{nickname: nickname} when is_binary(nickname) -> nickname
        _ -> nil
      end

    {:error, :member_programming_not_entitled,
     %{user_id: member_id, nickname: nickname, reason: to_string(reason)}}
  end
end
