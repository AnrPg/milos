defmodule Palee.Email.Commands.DeliverEmail do
  @moduledoc """
  One delivery attempt of an outbox message (ADR-203), run by
  `Palee.Workers.DeliverEmailJob`. Returns what the job should answer Oban:

    * `:ok` - sent, or nothing left to do (gone, already sent, suppressed,
      given up);
    * `{:snooze, seconds}` - over today's budget: `deferred` to the next UTC
      day;
    * `{:error, reason}` - the provider failed; retried with backoff;
    * `{:cancel, reason}` - permanent failure (an SMTP 5xx, an unreadable
      body): `failed` without retrying.

  The body is cleared once the email is sent or given up on, so the outbox
  keeps no readable link longer than it must.
  """

  require Logger

  alias Palee.Email.Domain.{Address, DeliveryPolicy, SendingPolicy}
  alias Palee.Email.Message
  alias Palee.Infrastructure.Security.DataCipher

  @done ~w(sent suppressed failed)

  def call(message_id, %{attempt: attempt, max_attempts: max_attempts}, %DateTime{} = now) do
    store = Palee.Email.message_store()

    case store.get(message_id) do
      nil -> :ok
      %Message{status: status} when status in @done -> :ok
      message -> attempt(store, message, attempt >= max_attempts, now)
    end
  end

  defp attempt(store, message, last?, now) do
    if store.suppressed?(Address.digest(message.to_address)) do
      {:ok, message} = store.update(message, %{status: "suppressed", encrypted_body: nil})
      Palee.Email.emit(:suppressed, message)
      :ok
    else
      case on_send(store, String.to_existing_atom(message.category), now) do
        :send ->
          send(store, message, last?, now)

        {:defer, until} ->
          {:ok, message} = store.update(message, %{status: "deferred", scheduled_at: until})
          Palee.Email.emit(:deferred, message)
          {:snooze, max(DateTime.diff(until, now), 1)}
      end
    end
  end

  defp on_send(store, category, now) do
    sent_today = store.count_sent_since(SendingPolicy.day_start(now))
    SendingPolicy.on_send(category, sent_today, Palee.Email.budget(), now)
  end

  defp send(store, message, last?, now) do
    result =
      with {:ok, %{"text" => text, "html" => html}} <- body(message) do
        Palee.Email.sender().deliver(%{
          to: message.to_address,
          subject: message.subject,
          text: text,
          html: html,
          message_id: message.message_id
        })
      end

    case result do
      {:ok, _metadata} ->
        {:ok, message} =
          store.update(message, %{
            status: "sent",
            sent_at: now,
            attempts: message.attempts + 1,
            last_error: nil,
            encrypted_body: nil,
            scheduled_at: nil
          })

        Palee.Email.emit(:sent, message)
        :ok

      {:error, reason} ->
        failed(store, message, reason, last?)
    end
  end

  defp failed(store, message, reason, last?) do
    permanent? = DeliveryPolicy.permanent?(reason)
    error = DeliveryPolicy.describe(reason)

    if permanent? or last? do
      {:ok, message} =
        store.update(message, %{
          status: "failed",
          attempts: message.attempts + 1,
          last_error: error,
          encrypted_body: nil
        })

      Palee.Email.emit(:failed, message, %{reason: error})
      if permanent?, do: {:cancel, reason}, else: {:error, reason}
    else
      {:ok, _message} =
        store.update(message, %{status: "queued", attempts: message.attempts + 1, last_error: error})

      Logger.warning("email_delivery_retry message=#{message.id} kind=#{message.kind} reason=#{error}")
      {:error, reason}
    end
  end

  defp body(%Message{encrypted_body: nil}), do: {:error, :undecryptable}

  defp body(%Message{encrypted_body: encrypted}) do
    with {:ok, json} <- DataCipher.decrypt(encrypted),
         {:ok, %{"text" => _, "html" => _} = body} <- Jason.decode(json) do
      {:ok, body}
    else
      _unreadable -> {:error, :undecryptable}
    end
  end
end
