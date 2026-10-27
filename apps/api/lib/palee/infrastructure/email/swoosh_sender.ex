defmodule Palee.Infrastructure.Email.SwooshSender do
  @moduledoc """
  Sends one outbox email through `Palee.Mailer` (ADR-203), from the
  configured `mail_from` and with the Message-ID the outbox stored, so a
  retry carries the same one and a provider event can be matched to the row.
  """

  @behaviour Palee.Email.Ports.Sender

  require Logger

  import Swoosh.Email

  alias Palee.Mailer

  # ADR-212: the only extra headers an outbox email may carry.
  @extra_headers ~w(List-Unsubscribe List-Unsubscribe-Post)

  @impl true
  def deliver(%{to: to, subject: subject, text: text, html: html, message_id: message_id} = email) do
    mail_from = Application.fetch_env!(:palee, :mail_from)

    new()
    |> to(to)
    |> from({Keyword.fetch!(mail_from, :name), Keyword.fetch!(mail_from, :address)})
    |> subject(subject)
    |> text_body(text)
    |> html_body(html)
    |> header("Message-ID", message_id)
    |> extra_headers(Map.get(email, :headers) || %{})
    |> safe_deliver()
  end

  defp extra_headers(email, headers) do
    headers
    |> Map.take(@extra_headers)
    |> Enum.reduce(email, fn {name, value}, email ->
      header(email, name, String.replace(value, ~r/[\r\n]+/, ""))
    end)
  end

  # Swoosh's Local adapter (dev only) talks to a GenServer a release does not
  # start, and a provider timeout raises the same way: Mailer.deliver/1 exits
  # the calling process instead of returning an error (see
  # SendOwnerInvitationEmail). The worker must see a plain error to retry.
  defp safe_deliver(email) do
    case Mailer.deliver(email) do
      {:ok, _metadata} = sent ->
        sent

      {:error, reason} = error ->
        Logger.error("Palee.Mailer.deliver/1 failed: #{inspect(reason)}")
        error
    end
  catch
    :exit, reason ->
      Logger.error("Palee.Mailer.deliver/1 exited: #{inspect(reason)}")
      {:error, :mail_delivery_unavailable}
  end
end
