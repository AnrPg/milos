defmodule MilosTraining.Organizations.Domain.MembershipPolicy do
  @moduledoc false

  @roles [:owner, :admin, :coach, :member, :athlete]
  @statuses [:invited, :active, :suspended, :revoked]
  @invitation_managers [:owner, :admin]

  def roles, do: @roles
  def statuses, do: @statuses
  def authorized_status?(status), do: status == :active
  def can_manage_invitations?(role), do: role in @invitation_managers
end
