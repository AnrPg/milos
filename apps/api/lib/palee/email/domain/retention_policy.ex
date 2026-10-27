defmodule Palee.Email.Domain.RetentionPolicy do
  @moduledoc """
  How long the outbox keeps its records (ADR-212). Bodies are already
  cleared once an email is sent or given up on (ADR-203); the remaining
  metadata (address, subject, status) is kept 90 days for the delivery
  views and the provider's late events, then deleted with its provider
  events. Link tokens are deleted 7 days after they were used or expired,
  so a person who opens an old link still gets "used"/"expired" for a week
  instead of "invalid". Messages still waiting to send are never deleted.
  """

  @message_days 90
  @link_token_days 7

  @doc "The days a message is kept."
  def message_days, do: @message_days

  @doc "The days a spent or expired link token is kept."
  def link_token_days, do: @link_token_days

  @doc "Messages inserted before this are deleted (unless still waiting)."
  def messages_before(%DateTime{} = now), do: DateTime.add(now, -@message_days, :day)

  @doc "Link tokens used or expired before this are deleted."
  def link_tokens_before(%DateTime{} = now), do: DateTime.add(now, -@link_token_days, :day)

  @doc "Statuses that still have something to do: never purged."
  def pending_statuses, do: ~w(queued deferred)
end
