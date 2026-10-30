defmodule Palee.Partners.Domain.MatchPolicy do
  @moduledoc """
  A match's life (ADR-169 §4, §7; one per pair since ADR-280). Pure.

  The pair is stored ordered (`user_a_id < user_b_id`), at most one active
  match per pair. Either person ends it (`unmatched`); a block (`blocked`),
  a report (`reported`) or the Palee team suspending one of them
  (`suspended`) end it too. Its conversation takes messages only while the
  match is active; otherwise it is read-only.
  """

  @statuses ~w(active ended)
  @end_reasons ~w(unmatched blocked reported suspended)

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

  @doc "The changes that end an active match; `actor_id` is nil when the Palee team ends it."
  def end_changes(%{status: "active"}, reason, actor_id, now) when reason in @end_reasons,
    do: {:ok, %{status: "ended", end_reason: reason, ended_by_id: actor_id, ended_at: now}}

  def end_changes(%{status: "ended"}, _reason, _actor_id, _now),
    do: {:error, :partner_match_ended}

  def end_changes(_match, _reason, _actor_id, _now), do: {:error, :invalid_end_reason}

  @doc "Whether the conversation takes new messages."
  def can_message?(match) do
    if active?(match), do: :ok, else: {:error, :partner_match_read_only}
  end

  def read_only?(match), do: can_message?(match) != :ok
end
