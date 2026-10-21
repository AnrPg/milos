defmodule Palee.Partners.Domain.MatchPolicy do
  @moduledoc """
  A match's life (ADR-169 §4, §7). Pure.

  The pair is stored ordered (`user_a_id < user_b_id`). Either person ends
  it (`unmatched`); a block, a report, leaving the club or staff hiding a
  profile end it too. Its conversation is writable only while the match is
  active and both people still belong to the club; otherwise it is
  read-only.
  """

  @statuses ~w(active ended)
  @end_reasons ~w(unmatched blocked reported left hidden)

  def statuses, do: @statuses
  def end_reasons, do: @end_reasons

  @doc "The ordered pair."
  def pair(a, b) when a < b, do: {a, b}
  def pair(a, b), do: {b, a}

  def pair_key({a, b}), do: "partner_pair:#{a}:#{b}"

  def party?(%{user_a_id: id}, id) when is_binary(id), do: true
  def party?(%{user_b_id: id}, id) when is_binary(id), do: true
  def party?(_match, _user_id), do: false

  def other(%{user_a_id: id, user_b_id: other}, id), do: other
  def other(%{user_b_id: id, user_a_id: other}, id), do: other

  @doc "The read mark field of `user_id`'s side."
  def read_field(%{user_a_id: id}, id), do: :a_read_at
  def read_field(%{user_b_id: id}, id), do: :b_read_at

  def read_at(match, user_id), do: Map.get(match, read_field(match, user_id))

  def active?(%{status: "active"}), do: true
  def active?(_match), do: false

  @doc "The changes that end an active match."
  def end_changes(%{status: "active"}, reason, actor_id, now) when reason in @end_reasons,
    do: {:ok, %{status: "ended", end_reason: reason, ended_by_id: actor_id, ended_at: now}}

  def end_changes(%{status: "ended"}, _reason, _actor_id, _now),
    do: {:error, :partner_match_ended}

  def end_changes(_match, _reason, _actor_id, _now), do: {:error, :invalid_end_reason}

  @doc "Whether the conversation takes new messages."
  def can_message?(match, both_members?) do
    if active?(match) and both_members?, do: :ok, else: {:error, :partner_match_read_only}
  end

  def read_only?(match, both_members?), do: can_message?(match, both_members?) != :ok
end
