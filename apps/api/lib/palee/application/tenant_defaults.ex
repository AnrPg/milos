defmodule Palee.Application.TenantDefaults do
  @moduledoc """
  The defaults every new organization starts with, whichever way it is
  created (ADR-133): Workouts' default scale levels (ADR-128), the gym's
  club with its built-in channels (ADR-138) and the default platform plan
  of its kind (ADR-170).

  It is handed to Organizations as the `seed_defaults` of a creation, so it
  runs inside the creation transaction in the new tenant's scope: an error
  here rolls the organization back.
  """

  alias Palee.{Community, PlatformPlans, Workouts}

  def call(%{organization_id: organization_id, user_id: _user_id} = scope)
      when is_binary(organization_id) do
    with {:ok, scale_levels} <- Workouts.seed_default_scale_levels(scope),
         {:ok, club} <- Community.provision_gym_club(scope),
         {:ok, subscription} <- PlatformPlans.ensure_subscription(scope) do
      {:ok, %{scale_levels: scale_levels, gym_club: club, subscription: subscription}}
    end
  end

  @doc """
  ADR-185: the defaults of a person's own organiser organisation: only what
  events need (their club, named after the person, and the free organiser
  plan). No scale levels or anything else a gym console would show.
  """
  def organiser(club_name) when is_binary(club_name) do
    fn scope ->
      with {:ok, club} <- Community.provision_gym_club(scope, club_name),
           {:ok, subscription} <- PlatformPlans.ensure_subscription(scope) do
        {:ok, %{gym_club: club, subscription: subscription}}
      end
    end
  end

  @doc """
  ADR-170: the defaults of an independent coach's practice: the same as any
  organization, with the club named after the coach («Team Νίκος»).
  """
  def coach_practice(team_name) when is_binary(team_name) do
    fn scope ->
      with {:ok, defaults} <- call(scope),
           {:ok, club} <- Community.provision_gym_club(scope, team_name) do
        {:ok, %{defaults | gym_club: club}}
      end
    end
  end
end
