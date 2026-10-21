defmodule Palee.Community.Domain.ClubPolicy do
  @moduledoc """
  Open clubs (ADR-143, board 7 Q6): clubs a gym's staff run for anyone,
  members of the gym or not. Pure.

  Staff of the gym create and run them. Joining an `open` club lets you in;
  an `approval` club waits for staff. Every open club starts with
  announcements (staff write) and a general channel everyone in it writes to.
  """

  @join_policies ~w(open approval)

  @channels [
    %{kind: "announcements", write_policy: "staff", membership: "everyone", position: 0},
    %{kind: "general", write_policy: "members", membership: "everyone", position: 1}
  ]

  def join_policies, do: @join_policies
  def channels, do: @channels

  @doc "The membership status joining gives."
  def join_status(%{join_policy: "open"}), do: "active"
  def join_status(%{join_policy: "approval"}), do: "pending"

  @doc "Only staff of the gym that runs it manage an open club."
  def can_manage?(role), do: role == "staff"

  @doc """
  A person's role in an open club: staff when they hold a staff role at the
  gym that runs it, a member when their membership is active.
  """
  def role(gym_role, _membership_status) when gym_role == "staff", do: "staff"
  def role(_gym_role, "active"), do: "member"
  def role(_gym_role, _status), do: nil
end
