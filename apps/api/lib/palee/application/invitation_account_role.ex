defmodule Palee.Application.InvitationAccountRole do
  @moduledoc """
  ADR-095 surface role an invitation gives the account: every staff role
  works in the staff shell, an athlete invitation makes an athlete, the rest
  a member. A profile that already exists is only ever lifted (member to
  athlete or staff, athlete to staff), never lowered by joining another box.
  """

  @staff_roles [:owner, :admin, :coach, :front_desk, :accountant, :janitor]
  @rank %{member: 0, athlete: 1, admin: 2}

  def for_invitation(role) when role in @staff_roles, do: :admin
  def for_invitation(:athlete), do: :athlete
  def for_invitation(_role), do: :member

  def promotes?(current, target),
    do: Map.get(@rank, target, 0) > Map.get(@rank, current, 0)
end
