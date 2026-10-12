defmodule MilosTraining.Organizations.Domain.MembershipPolicy do
  @moduledoc false

  @roles [:owner, :admin, :coach, :member, :athlete]
  @statuses [:invited, :active, :suspended, :revoked]

  # No rights-per-role report separates coaches from admins yet, so coaches
  # hold admin rights (ADR-098). Change this list when that report exists.
  @admin_roles [:owner, :admin, :coach]

  def roles, do: @roles
  def admin_roles, do: @admin_roles
  def statuses, do: @statuses
  def authorized_status?(status), do: status == :active

  # `can_manage_invitations?/1` lived here unused. The retirement plan expected
  # F-06 to make it live, but that fix went through can_grant_role?/2 instead,
  # and membership-management authorization is now expressed uniformly as
  # TenantAuthorization.authorize(context, [:owner, :admin]) in IssueInvitation,
  # SetMembershipRole and SetMembershipStatus. A second, unused spelling of the
  # same rule is what made RequireRole (F-02) dangerous, so it is removed
  # rather than left as a plausible-looking alternative.

  @doc """
  Whether `issuer_role` is allowed to grant `target_role` to someone else.
  An account can never grant a role more privileged than its own - `@roles`
  is ordered from most to least privileged, so this holds when the issuer's
  rank is at or above the target role's rank.
  """
  def can_grant_role?(issuer_role, target_role) do
    role_rank(issuer_role) <= role_rank(target_role)
  end

  # A coach ranks as an admin while coaches hold admin rights (ADR-098).
  defp role_rank(:coach), do: role_rank(:admin)
  defp role_rank(role), do: Enum.find_index(@roles, &(&1 == role)) || length(@roles)
end
