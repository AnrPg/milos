defmodule Palee.Application.OrganizationPlan do
  @moduledoc """
  ADR-170: the organization's platform plan as its owner and admins see it
  (plan, status, notice, seats used against the limits), and the staff-seat
  check every path that hands out a staff role runs first.
  """

  alias Palee.{Organizations, PlatformPlans}

  def get(context, now \\ DateTime.utc_now()) do
    with {:ok, subscription} <- PlatformPlans.get_subscription(context),
         {:ok, usage} <- Organizations.seat_usage(context, now) do
      {:ok, PlatformPlans.describe(subscription, usage, now)}
    end
  end

  @doc """
  Refuses one more staff seat when the plan is full. Vendors act through the
  platform console and never pass here.
  """
  def check_staff_seat(context, now \\ DateTime.utc_now()) do
    case Organizations.seat_usage(context, now) do
      {:ok, %{"staff_seats" => used}} -> PlatformPlans.check_limit(context, "staff_seats", used)
      # Someone who may not grant staff roles is refused by Organizations itself.
      {:error, :forbidden} -> :ok
      error -> error
    end
  end

  @doc "The seat check for a role change: only a new staff holder takes a seat."
  def check_role_change(context, user_id, roles) do
    if takes_staff_seat?(roles) and not Organizations.staff_member?(context, user_id),
      do: check_staff_seat(context),
      else: :ok
  end

  @doc "The seat check for an invitation: only a staff invitation reserves a seat."
  def check_invitation(context, role) do
    if takes_staff_seat?([role]), do: check_staff_seat(context), else: :ok
  end

  defp takes_staff_seat?(roles) do
    staff = Enum.map(Organizations.staff_and_admin_roles(), &Atom.to_string/1)
    roles |> List.wrap() |> Enum.any?(&(to_string(&1) in staff))
  end
end
