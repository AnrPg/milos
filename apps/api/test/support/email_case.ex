defmodule Palee.EmailCase do
  @moduledoc """
  Test helpers for the email outbox (ADR-203). `import Palee.EmailCase` (or
  `use Palee.EmailCase`) in any `DataCase`/`ConnCase` test:

      {:ok, _} = MyFeature.do_something()

      message = assert_email_enqueued(kind: :verify_email, to: "jo@x.test")
      assert message.text =~ "Confirm"
      assert message.html =~ "Confirm"

      refute_email_enqueued(kind: :verify_email, to: "other@x.test")

      # Send what is queued through the Swoosh test adapter:
      deliver_enqueued_emails()
      assert_email_sent(subject: message.subject)   # Swoosh.TestAssertions

  Filters: `kind` (atom or string), `to`, `status`, `category`,
  `organization_id`, `user_id`, `login_id`, `idempotency_key`, plus
  `subject`, `text` and `html` (a string the field must contain, or a
  regex). Returned messages carry their decrypted bodies in `:text` and
  `:html` (nil once sent: the outbox clears them).
  """

  import ExUnit.Assertions

  alias Palee.Email.Message
  alias Palee.Infrastructure.Security.DataCipher

  defmacro __using__(_opts) do
    quote do
      import Palee.EmailCase
    end
  end

  @store_filters ~w(kind to status category organization_id user_id login_id idempotency_key)a

  @doc "Every outbox message matching `filters`, newest first, with `:text` and `:html`."
  def enqueued_emails(filters \\ []) do
    {store_filters, content_filters} = Keyword.split(filters, @store_filters)

    store_filters
    |> Enum.map(fn
      {:kind, kind} -> {:kind, to_string(kind)}
      {:to, to} -> {:to_address, String.downcase(String.trim(to))}
      {:category, category} -> {:category, to_string(category)}
      {:status, status} -> {:status, to_string(status)}
      other -> other
    end)
    |> Palee.Email.message_store().list()
    |> Enum.map(&with_bodies/1)
    |> Enum.filter(fn message ->
      Enum.all?(content_filters, fn {field, expected} ->
        matches?(Map.get(message, field), expected)
      end)
    end)
  end

  @doc "Asserts exactly one message matches `filters` and returns it."
  def assert_email_enqueued(filters) do
    case enqueued_emails(filters) do
      [message] ->
        message

      [] ->
        flunk("""
        Expected an email matching #{inspect(filters)} to be enqueued, found none.
        Enqueued: #{inspect(Enum.map(enqueued_emails(), &{&1.kind, &1.to_address, &1.status}))}
        """)

      many ->
        flunk("Expected one email matching #{inspect(filters)}, found #{length(many)}.")
    end
  end

  @doc "Asserts no message matches `filters`."
  def refute_email_enqueued(filters) do
    case enqueued_emails(filters) do
      [] -> :ok
      found -> flunk("Expected no email matching #{inspect(filters)}, found #{length(found)}.")
    end
  end

  @doc """
  Runs `DeliverEmailJob` for every `queued` or `deferred` message (oldest
  first), as Oban would, and returns how many were sent. With the Swoosh
  test adapter each sent email reaches the calling test process, so
  `Swoosh.TestAssertions` work afterwards.
  """
  def deliver_enqueued_emails(now \\ DateTime.utc_now()) do
    (enqueued_emails(status: "queued") ++ enqueued_emails(status: "deferred"))
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.count(fn message ->
      Palee.Email.deliver(message.id, %{attempt: 1, max_attempts: 8}, now) == :ok and
        match?({:ok, %{status: "sent"}}, Palee.Email.status(message.id))
    end)
  end

  @doc "Decrypts a message's bodies into `:text` and `:html` (nil when cleared)."
  def with_bodies(%Message{encrypted_body: nil} = message), do: message

  def with_bodies(%Message{encrypted_body: encrypted} = message) do
    {:ok, json} = DataCipher.decrypt(encrypted)
    %{"text" => text, "html" => html} = Jason.decode!(json)
    %{message | text: text, html: html}
  end

  defp matches?(nil, _expected), do: false
  defp matches?(value, %Regex{} = expected), do: Regex.match?(expected, value)
  defp matches?(value, expected) when is_binary(expected), do: String.contains?(value, expected)
end
