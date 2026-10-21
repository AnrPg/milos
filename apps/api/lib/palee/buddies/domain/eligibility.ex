defmodule Palee.Buddies.Domain.Eligibility do
  @moduledoc """
  Who you can ask (ADR-160 §1, board 15 Q2 «Anyone you know here, or a
  link»): your coach, someone you share a gym or open club with, someone you
  follow or who follows you, or anyone through an invite link you send
  yourself. A stranger can never be invited by id.
  """

  @relations ~w(coach club follow)

  def relations, do: @relations

  @doc "Whether `relation` (from the relation lookup, nil for none) lets you invite."
  def check(_inviter_id, invitee_id, _relation) when not is_binary(invitee_id),
    do: {:error, :not_found}

  def check(user_id, user_id, _relation), do: {:error, :cannot_buddy_self}
  def check(_inviter_id, _invitee_id, relation) when relation in @relations, do: :ok
  def check(_inviter_id, _invitee_id, _relation), do: {:error, :not_eligible_for_buddy}

  @doc "Search terms shorter than this list only coaches and follows."
  def min_search_length, do: 2

  @doc "A trimmed search term, or nil when too short to widen the search."
  def search_term(term) when is_binary(term) do
    term = String.trim(term)
    if String.length(term) >= min_search_length(), do: String.slice(term, 0, 64), else: nil
  end

  def search_term(_term), do: nil
end
