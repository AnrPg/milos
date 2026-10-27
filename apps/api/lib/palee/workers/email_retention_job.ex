defmodule Palee.Workers.EmailRetentionJob do
  @moduledoc """
  Daily: deletes outbox messages older than 90 days (with their provider
  events) and link tokens spent or expired more than 7 days ago (ADR-212,
  `Palee.Email.purge/1`). Messages still queued or deferred are kept.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    %{messages: messages, link_tokens: link_tokens} = Palee.Email.purge()
    Logger.info("email_retention messages=#{messages} link_tokens=#{link_tokens}")
    :ok
  end
end
