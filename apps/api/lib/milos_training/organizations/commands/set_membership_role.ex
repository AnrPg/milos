defmodule MilosTraining.Organizations.Commands.SetMembershipRole do
  @moduledoc """
  Changes an account's role **within one organization** (F-29).

  Roles belong to memberships, not to accounts. The previous admin-facing
  path wrote the global `users.role`, which meant an admin of one gym could
  change what an account was everywhere it belonged — and could do it to
  accounts that had never been a member of their gym at all, since the target
  was looked up by id with no membership check.

  Scoping the lookup to `context.organization_id` closes both halves: an
  account outside the acting organization simply has no membership to find.
  """

  alias MilosTraining.Organizations.Domain.{MembershipPolicy, TenantAuthorization}
  alias MilosTraining.Organizations.OrganizationStore
  alias MilosTraining.{Scheduling, Workouts}

  def call(context, user_id, role) when is_binary(user_id) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]),
         {:ok, role} <- normalize_role(role),
         {:ok, membership} <- fetch_membership(context, user_id),
         :ok <- refuse_self_change(context, membership),
         :ok <- authorize_role_ceiling(context.role, role),
         :ok <- authorize_role_ceiling(context.role, membership.role),
         :ok <- reconcile_role_owned_state(context, membership, role) do
      OrganizationStore.update_membership_role(
        context.organization_id,
        membership.id,
        role
      )
    end
  end

  def call(_context, _user_id, _role), do: {:error, :not_found}

  defp fetch_membership(context, user_id) do
    case OrganizationStore.get_membership(context.organization_id, user_id) do
      nil -> {:error, :not_found}
      membership -> {:ok, membership}
    end
  end

  # Leaving a role abandons the state that role owned. Carried over from the
  # old global-role path, but now scoped to the organization the change was
  # made in, so losing :athlete at one gym cannot archive assignments at
  # another.
  defp reconcile_role_owned_state(_context, %{role: role}, role), do: :ok

  defp reconcile_role_owned_state(context, %{role: :member, user_id: user_id}, _new_role) do
    case Scheduling.cancel_active_future_bookings_for_user(context, user_id) do
      {:ok, _booking_ids} -> :ok
      error -> error
    end
  end

  defp reconcile_role_owned_state(_context, %{role: :athlete, user_id: user_id}, _new_role) do
    # TODO(F-18): only a legacy un-scoped arity exists for assignments, so this
    # still reaches across organizations. Tracked as P3.1.
    case Workouts.archive_active_assignments_for_athlete(user_id) do
      {:ok, _assignment_ids} -> :ok
      error -> error
    end
  end

  defp reconcile_role_owned_state(_context, _membership, _new_role), do: :ok

  defp refuse_self_change(context, membership) do
    if membership.user_id == context.user_id do
      {:error, :cannot_change_own_membership}
    else
      :ok
    end
  end

  # Checked against both the requested role and the target's current role: an
  # admin may neither promote someone above themselves nor demote an owner.
  defp authorize_role_ceiling(actor_role, subject_role) do
    if MembershipPolicy.can_grant_role?(actor_role, subject_role) do
      :ok
    else
      {:error, :role_ceiling_exceeded}
    end
  end

  defp normalize_role(role) when is_atom(role), do: validate_role(role)

  defp normalize_role(role) when is_binary(role) do
    MembershipPolicy.roles()
    |> Enum.find(&(Atom.to_string(&1) == role))
    |> validate_role()
  end

  defp normalize_role(_role), do: {:error, [role: "is invalid"]}

  defp validate_role(role) when is_atom(role) and not is_nil(role) do
    if role in MembershipPolicy.roles(), do: {:ok, role}, else: {:error, [role: "is invalid"]}
  end

  defp validate_role(_role), do: {:error, [role: "is invalid"]}
end
