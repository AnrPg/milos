defmodule Palee.Organizations.Commands.SetMembershipRole do
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

  alias Palee.Organizations.Domain.{MembershipPolicy, TenantAuthorization}
  alias Palee.Application.BroadcastUserSync
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.OrganizationStore
  alias Palee.{Finance, Scheduling, Workouts}

  @doc "Replaces the target's roles with one role (single-role callers)."
  def call(context, user_id, role) when is_binary(user_id) do
    case normalize_role(role) do
      {:ok, role} -> set_roles(context, user_id, [role])
      error -> error
    end
  end

  def call(_context, _user_id, _role), do: {:error, :not_found}

  @doc """
  Sets the full role set of an account in the context's gym (ADR-099). The
  actor needs to be allowed to grant every role added or removed, so an admin
  can neither promote anyone to admin or owner nor demote an owner, and a gym
  always keeps an owner.
  """
  def set_roles(context, user_id, roles) when is_binary(user_id) do
    case TenantAuthorization.authorize_capability(context, :grant_staff_roles) do
      # organization_memberships is a root tenant table: lookups, the update and
      # the staff broadcast run in the acting member's tenant scope (TD-046).
      :ok -> RepoContext.run(context, fn -> change_roles(context, user_id, roles) end)
      error -> error
    end
  end

  def set_roles(_context, _user_id, _roles), do: {:error, :not_found}

  defp change_roles(context, user_id, roles) do
    with {:ok, roles} <- MembershipPolicy.normalize_roles(roles),
         {:ok, membership} <- fetch_membership(context, user_id),
         :ok <- refuse_self_change(context, membership),
         changed = symmetric_difference(roles, membership.roles),
         :ok <- authorize_role_ceiling(TenantAuthorization.roles(context), changed),
         :ok <- keep_an_owner(context, membership, roles) do
      OrganizationStore.transaction(fn ->
        with :ok <- reconcile_role_owned_state(context, membership, roles) do
          OrganizationStore.update_membership_roles(
            context.organization_id,
            membership.id,
            roles
          )
        end
      end)
      |> broadcast_change(context)
    end
  end

  defp symmetric_difference(a, b), do: Enum.uniq((a -- b) ++ (b -- a))

  defp keep_an_owner(context, membership, roles) do
    losing_owner? = :owner in membership.roles and :owner not in roles

    other_owner? =
      context.organization_id
      |> OrganizationStore.list_organization_memberships()
      |> Enum.any?(
        &(&1.id != membership.id and &1.status == :active and :owner in (&1.roles || [&1.role]))
      )

    if losing_owner? and not other_owner?, do: {:error, :last_owner}, else: :ok
  end

  # Restores the notification UpdateUserRole used to send, now carrying the
  # organization: a role only changed inside one tenant, so telling admins of
  # every other organization about it would be a small cross-tenant leak.
  defp broadcast_change({:ok, membership} = result, context) do
    BroadcastUserSync.for_user(membership.user_id, ["session"],
      reason: "role_changed",
      payload: %{
        role: to_string(membership.role),
        roles: Enum.map(membership.roles, &to_string/1),
        organization_id: context.organization_id
      }
    )

    admin_ids =
      context.organization_id
      |> OrganizationStore.list_organization_memberships()
      |> Enum.filter(
        &(&1.status == :active and Enum.any?(&1.roles, fn role -> role in [:owner, :admin] end))
      )
      |> Enum.map(& &1.user_id)

    BroadcastUserSync.for_users(admin_ids, ["admin_athletes", "admin_finance"],
      reason: "user_role_changed",
      payload: %{
        user_id: membership.user_id,
        role: to_string(membership.role),
        organization_id: context.organization_id
      }
    )

    result
  end

  defp broadcast_change(result, _context), do: result

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
  defp reconcile_role_owned_state(context, membership, roles) do
    Enum.reduce_while(membership.roles -- roles, :ok, fn lost, :ok ->
      case abandon_role_state(context, lost, membership.user_id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # ADR-125: members may also hold personal assignments and class variants;
  # leaving the role archives them like leaving :athlete does.
  defp abandon_role_state(context, :member, user_id) do
    with {:ok, release_facts} <-
           Scheduling.cancel_active_future_bookings_for_user(context, user_id),
         :ok <- release_booking_entitlements(context, release_facts),
         {:ok, _assignment_ids} <-
           Workouts.archive_active_assignments_for_athlete(context, user_id) do
      :ok
    end
  end

  defp abandon_role_state(context, :athlete, user_id) do
    case Workouts.archive_active_assignments_for_athlete(context, user_id) do
      {:ok, _assignment_ids} -> :ok
      error -> error
    end
  end

  defp abandon_role_state(_context, _role, _user_id), do: :ok

  defp release_booking_entitlements(context, release_facts) do
    Enum.reduce_while(release_facts, :ok, fn fact, :ok ->
      case Finance.release_entitlement_source(
             context,
             fact.user_id,
             "scheduling",
             fact.scheduled_class_id,
             :class_visits,
             %{
               reason: "Membership role changed",
               idempotency_key: "role-transition-booking-release:#{fact.booking_id}"
             }
           ) do
        {:ok, _entry} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp refuse_self_change(context, membership) do
    if membership.user_id == context.user_id do
      {:error, :cannot_change_own_membership}
    else
      :ok
    end
  end

  # Every added or removed role must be one the actor may grant: an admin may
  # neither promote someone to admin or owner nor demote an owner.
  defp authorize_role_ceiling(actor_roles, changed_roles) do
    if Enum.all?(changed_roles, &MembershipPolicy.can_grant_role?(actor_roles, &1)) do
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
