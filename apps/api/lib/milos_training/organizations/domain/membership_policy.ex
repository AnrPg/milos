defmodule MilosTraining.Organizations.Domain.MembershipPolicy do
  @moduledoc false

  @roles [:owner, :admin, :coach, :member, :athlete]
  @statuses [:invited, :active, :suspended, :revoked]
  @invitation_managers [:owner, :admin]

  def roles, do: @roles
  def statuses, do: @statuses
  def authorized_status?(status), do: status == :active
  def can_manage_invitations?(role), do: role in @invitation_managers

  @doc """
  Whether `issuer_role` is allowed to grant `target_role` to someone else.
  An account can never grant a role more privileged than its own - `@roles`
  is ordered from most to least privileged, so this holds when the issuer's
  rank is at or above the target role's rank.
  """
  def can_grant_role?(issuer_role, target_role) do
    role_rank(issuer_role) <= role_rank(target_role)
  end

  defp role_rank(role), do: Enum.find_index(@roles, &(&1 == role)) || length(@roles)
end
