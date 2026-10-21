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
