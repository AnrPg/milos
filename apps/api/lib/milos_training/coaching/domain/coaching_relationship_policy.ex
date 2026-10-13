defmodule MilosTraining.Coaching.Domain.CoachingRelationshipPolicy do
  @moduledoc """
  Who may start which coaching relationship (ADR-100): owners and admins
  assign any coach to any client; a coach may take an athlete (never a
  member) as their own client; a coach's invitation makes the invited client
  theirs. The coach must hold the coach role and the client a client role.
  """

  def origin(:assigned), do: "assigned"
  def origin(:self_assigned), do: "self_assigned"
  def origin(:invited), do: "invited"

  def can_start?(:self_assigned, coach_roles, client_roles) do
    cond do
      :coach not in coach_roles -> {:error, :not_a_coach}
      :athlete not in client_roles -> {:error, :only_athletes_self_assigned}
      true -> :ok
    end
  end

  def can_start?(_origin, coach_roles, client_roles) do
    cond do
      :coach not in coach_roles -> {:error, :not_a_coach}
      not Enum.any?(client_roles, &(&1 in [:member, :athlete])) -> {:error, :not_a_client}
      true -> :ok
    end
  end
end
