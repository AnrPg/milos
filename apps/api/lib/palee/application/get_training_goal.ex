defmodule Palee.Application.GetTrainingGoal do
  @moduledoc """
  A person's weekly workout goal as the API shows it (ADR-216): theirs, or
  the platform default with `is_default: true` until someone sets one.
  Staff callers are authorised by the controller (ADR-099/100); the database
  bounds the read to the person or the staff of their box.
  """

  alias Palee.Gamification
  alias Palee.Gamification.Domain.WeeklyGoal
  alias Palee.Organizations

  def call(context, member_id) do
    with :ok <- reachable(context, member_id) do
      Gamification.with_tenant_context(context, fn ->
        {:ok, member_id |> Gamification.get_training_goal() |> WeeklyGoal.present()}
      end)
    end
  end

  @doc """
  The person themselves, or staff of a box the person is an active member
  of; anyone else gets `:not_found`, never a database refusal.
  """
  def reachable(%{user_id: member_id}, member_id), do: :ok

  def reachable(%{organization_id: organization_id}, member_id)
      when is_binary(organization_id) do
    case Organizations.membership_standing(organization_id, member_id) do
      :member -> :ok
      _other -> {:error, :not_found}
    end
  end

  def reachable(_context, _member_id), do: {:error, :not_found}
end
