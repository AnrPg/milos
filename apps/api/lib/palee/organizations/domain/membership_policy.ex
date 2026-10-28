defmodule Palee.Organizations.Domain.MembershipPolicy do
  @moduledoc """
  Membership roles and who may grant them (ADR-099). A membership holds a set
  of roles; `@roles` is ordered from most to least privileged, and the first
  role of a set in that order is its primary role.
  """

  @roles [:owner, :admin, :coach, :front_desk, :accountant, :janitor, :member, :athlete]
  @statuses [:invited, :active, :suspended, :revoked]

  @staff_roles [:coach, :front_desk, :accountant, :janitor]
  @client_roles [:member, :athlete]

  # Roles that run the gym; used where a check predates capabilities.
  @admin_roles [:owner, :admin]

  def roles, do: @roles
  def staff_roles, do: @staff_roles
  def client_roles, do: @client_roles
  def admin_roles, do: @admin_roles
  def statuses, do: @statuses
  def authorized_status?(status), do: status == :active

  @doc """
  ADR-217: whether a role set makes someone a client of the business. Only a
  member or athlete role does; staff roles never imply one.
  """
  def client?(roles), do: Enum.any?(List.wrap(roles), &(parse_role(&1) in @client_roles))

  @doc "ADR-217: whether a role set holds any staff role (owner and admin included)."
  def staff?(roles),
    do: Enum.any?(List.wrap(roles), &(parse_role(&1) in (@admin_roles ++ @staff_roles)))

  @doc "ADR-217: the client role of a role set (`:athlete` before `:member`), or nil."
  def client_role(roles) do
    roles = Enum.map(List.wrap(roles), &parse_role/1)

    cond do
      :athlete in roles -> :athlete
      :member in roles -> :member
      true -> nil
    end
  end

  @doc """
  Whether an account holding `issuer_roles` may grant `target_role` to someone
  else: owners grant any role, admins grant staff and client roles, coaches
  and front desk invite clients, nobody else grants roles.
  """
  def can_grant_role?(issuer_roles, target_role) do
    issuer_roles = List.wrap(issuer_roles)

    cond do
      :owner in issuer_roles -> target_role in @roles
      :admin in issuer_roles -> target_role in @staff_roles or target_role in @client_roles
      Enum.any?(issuer_roles, &(&1 in [:coach, :front_desk])) -> target_role in @client_roles
      true -> false
    end
  end

  # The hierarchy (rights-per-account-type §4): owner › admin › staff ›
  # clients. Roles of one tier are peers.
  @tiers %{
    owner: 4,
    admin: 3,
    coach: 2,
    front_desk: 2,
    accountant: 2,
    janitor: 2,
    member: 1,
    athlete: 1
  }

  @doc "A role's rank in the hierarchy; higher outranks lower, equal ranks are peers."
  def tier(role), do: Map.get(@tiers, role, 0)

  @doc "The rank of a set's most privileged role (0 for none)."
  def top_tier(roles), do: roles |> List.wrap() |> Enum.map(&tier/1) |> Enum.max(fn -> 0 end)

  @doc """
  Whether an account holding `actor_roles` may act on someone else holding
  `target_roles`: only on people ranked below them. Owners also manage their
  co-owners, so a gym is never stuck with an owner who left.
  """
  def can_manage_member?(actor_roles, target_roles) do
    actor_roles = List.wrap(actor_roles)
    target_roles = List.wrap(target_roles)

    top_tier(actor_roles) > top_tier(target_roles) or
      (:owner in actor_roles and :owner in target_roles)
  end

  @doc """
  Whether someone holding `own_roles` may add or drop `role` on themselves:
  only roles ranked below their top role, which therefore never changes (an
  owner who also coaches stays owner).
  """
  def self_assignable_role?(own_roles, role), do: tier(role) < top_tier(own_roles)

  @doc """
  Checks a change of `current` roles to `requested` ones. On oneself only
  roles below one's top role move; on someone else the actor must outrank
  them and be allowed to grant every role added or removed.
  """
  def authorize_role_change(_actor_roles, current, requested, :self) do
    if Enum.all?(changed(current, requested), &self_assignable_role?(current, &1)),
      do: :ok,
      else: {:error, :own_top_role_locked}
  end

  def authorize_role_change(actor_roles, current, requested, :other) do
    if can_manage_member?(actor_roles, current) and
         Enum.all?(changed(current, requested), &can_grant_role?(actor_roles, &1)),
       do: :ok,
       else: {:error, :role_ceiling_exceeded}
  end

  defp changed(a, b), do: Enum.uniq((a -- b) ++ (b -- a))

  @doc "The most privileged role of a set."
  def primary_role(roles), do: Enum.find(@roles, &(&1 in roles))

  @doc "Parses a role set: known roles, deduplicated, in privilege order."
  def normalize_roles(roles) when is_list(roles) do
    parsed = Enum.map(roles, &parse_role/1)

    cond do
      parsed == [] -> {:error, :roles_required}
      Enum.any?(parsed, &is_nil/1) -> {:error, :invalid_role}
      true -> {:ok, Enum.filter(@roles, &(&1 in parsed))}
    end
  end

  def normalize_roles(_roles), do: {:error, :roles_required}

  defp parse_role(role) when role in @roles, do: role

  defp parse_role(role) when is_binary(role),
    do: Enum.find(@roles, &(Atom.to_string(&1) == role))

  defp parse_role(_role), do: nil
end
