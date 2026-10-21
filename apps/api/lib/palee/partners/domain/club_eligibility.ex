defmodule Palee.Partners.Domain.ClubEligibility do
  @moduledoc """
  Which clubs offer Partners (ADR-169 §2). Pure.

  Swipe only among members the gym verified (vision §7.3): a gym's own
  club (its active members), a PT squad or a season (the gym put people
  in), or an open club where staff approve or invite every member. Never an
  open club anyone can walk into, never an archived one, and never when the
  gym switched Partners off.
  """

  @verified_kinds ~w(gym pt_squad season)
  @verified_open_policies ~w(approval invite)

  def verified_kinds, do: @verified_kinds

  @doc "Whether the club's members are verified by the gym."
  def verified?(%{archived_at: %DateTime{}}), do: false
  def verified?(%{kind: kind}) when kind in @verified_kinds, do: true

  def verified?(%{kind: "open", join_policy: policy}) when policy in @verified_open_policies,
    do: true

  def verified?(_club), do: false

  @doc "`:ok` when the club offers Partners to its members."
  def check(club, gym_enabled?) do
    cond do
      not gym_enabled? -> {:error, :partners_disabled}
      not verified?(club) -> {:error, :partners_not_offered}
      true -> :ok
    end
  end

  def offered?(club, gym_enabled?), do: check(club, gym_enabled?) == :ok
end
