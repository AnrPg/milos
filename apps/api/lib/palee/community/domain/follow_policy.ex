defmodule Palee.Community.Domain.FollowPolicy do
  @moduledoc """
  How following works (ADR-142, D3; ADR-193 §2): following a private person
  is a request they accept, a public person is followed at once, and so is
  a box or an open club. Pure: callers pass the facts about the target.
  """

  @target_types ~w(user organization club)

  def target_types, do: @target_types

  @doc "The status a new follow starts in; a person target says whether it is public."
  def initial_status("user", %{public: true}), do: "active"
  def initial_status("user", _target), do: "requested"
  def initial_status(type, _target) when type in @target_types, do: "active"

  @doc """
  ADR-193 §1: two people are Buddies when each actively follows the other.
  `mine` and `theirs` are the two statuses ("none" when there is no follow).
  """
  def buddies?("active", "active"), do: true
  def buddies?(_mine, _theirs), do: false

  @doc """
  Whether `follower_id` may follow the target. `target` carries what the
  caller found: `nil` when it does not exist (or is not public).
  """
  def check(_follower_id, type, _target) when type not in @target_types,
    do: {:error, :invalid_follow_target}

  def check(follower_id, "user", %{id: follower_id}), do: {:error, :cannot_follow_self}
  def check(_follower_id, _type, nil), do: {:error, :not_found}
  # Open clubs arrive in P2-M4; until then no club is followable.
  def check(_follower_id, "club", %{kind: kind}) when kind != "open", do: {:error, :not_found}
  def check(_follower_id, _type, _target), do: :ok

  @doc "The relationship as clients see it."
  def status(nil), do: "none"
  def status(%{status: status}), do: status
end
