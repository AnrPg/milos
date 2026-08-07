defmodule MilosTraining.Organizations.Commands.SetMembershipStatus do
  @moduledoc """
  Suspends, revokes, or reinstates a membership (F-11).

  No de-authorization path existed before this: the only way to cut off a
  compromised or offboarded account was to delete the global `users` row,
  which removes their access to every other organization too.

  Nothing else needs to change for this to take effect —
  `TenantAuthorization.build/4` already refuses any membership whose status
  fails `MembershipPolicy.authorized_status?/1`, so flipping the status is
  enough to reject the account's next tenant-scoped request.
  """

  alias MilosTraining.Organizations.Domain.{MembershipPolicy, TenantAuthorization}
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.Organizations.OrganizationStore

  @settable_statuses [:active, :suspended, :revoked]

  def call(context, membership_id, status) when is_binary(membership_id) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]),
         {:ok, status} <- normalize_status(status),
         {:ok, membership} <- fetch_membership(context, membership_id),
         :ok <- refuse_self_change(context, membership),
         :ok <- authorize_role_ceiling(context.role, membership.role) do
      context.organization_id
      |> OrganizationStore.update_membership_status(membership_id, status)
      |> broadcast_change(context)
    end
  end

  def call(_context, _membership_id, _status), do: {:error, :not_found}

  # A suspended or revoked member keeps a valid access token until it expires;
  # TenantAuthorization will refuse them on the next request, but the client
  # should find out now rather than through a confusing failure.
  defp broadcast_change({:ok, membership} = result, context) do
    BroadcastUserSync.for_user(membership.user_id, ["session"],
      reason: "membership_status_changed",
      payload: %{
        status: to_string(membership.status),
        organization_id: context.organization_id
      }
    )

    result
  end

  defp broadcast_change(result, _context), do: result

  defp fetch_membership(context, membership_id) do
    case OrganizationStore.get_membership_by_id(context.organization_id, membership_id) do
      nil -> {:error, :not_found}
      membership -> {:ok, membership}
    end
  end

  # Without this an owner can revoke their own membership and lock the
  # organization out of its own admin surface.
  defp refuse_self_change(context, membership) do
    if membership.user_id == context.user_id do
      {:error, :cannot_change_own_membership}
    else
      :ok
    end
  end

  # Same ceiling as IssueInvitation (F-06): an account may never act on a
  # membership more privileged than its own.
  defp authorize_role_ceiling(actor_role, target_role) do
    if MembershipPolicy.can_grant_role?(actor_role, target_role) do
      :ok
    else
      {:error, :role_ceiling_exceeded}
    end
  end

  defp normalize_status(status) when is_atom(status), do: validate_status(status)

  defp normalize_status(status) when is_binary(status) do
    @settable_statuses
    |> Enum.find(&(Atom.to_string(&1) == status))
    |> validate_status()
  end

  defp normalize_status(_status), do: {:error, [status: "is invalid"]}

  defp validate_status(status) when status in @settable_statuses, do: {:ok, status}
  defp validate_status(_status), do: {:error, [status: "is invalid"]}
end
