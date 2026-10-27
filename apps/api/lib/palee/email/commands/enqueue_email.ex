defmodule Palee.Email.Commands.EnqueueEmail do
  @moduledoc """
  `Palee.Email.enqueue/4` (ADR-203): checks, renders and stores one email
  and its delivery job, in this order:

    1. the kind is registered and the address is valid;
    2. the demo gate (ADR-184): a `transactional` email for a business still
       in demo mode is refused (`:not_live`); `security` and `account`
       mail is the platform's, not the business's, and always goes;
    3. an existing message with the same `idempotency_key` is returned as is;
    4. the address is not suppressed (`:suppressed`);
    5. the kind's per-recipient throttle (`:throttled`);
    6. the daily budget: queued now, deferred to the next UTC day, or, for
       security mail past the hard cap, refused (`:over_budget`);
    7. the template renders; the body is encrypted and the row and its job
       are inserted in one transaction.
  """

  alias Palee.Email.Domain.{Address, SendingPolicy}
  alias Palee.Email.{Message, Templates}
  alias Palee.Infrastructure.Security.DataCipher
  alias Palee.Organizations
  alias Palee.Workers.DeliverEmailJob

  @day_seconds 86_400

  def call(kind, to, assigns, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    store = Palee.Email.message_store()

    with {:ok, template} <- Templates.fetch(kind),
         {:ok, address} <- Address.normalize(to),
         {:ok, category} <- category(template, opts),
         :ok <- live(category, Keyword.get(opts, :organization_id)) do
      case existing(store, Keyword.get(opts, :idempotency_key)) do
        %Message{} = message ->
          {:ok, message}

        nil ->
          with :ok <- not_suppressed(store, address),
               :ok <- throttle(store, template, kind, address, category, now),
               {:ok, schedule} <- budget(store, category, now) do
            insert(store, template, kind, address, assigns, category, schedule, opts)
          end
      end
    end
  end

  defp category(template, opts) do
    case Keyword.fetch(opts, :category) do
      {:ok, override} ->
        case SendingPolicy.category(override) do
          {:ok, category} -> {:ok, category}
          :error -> {:error, :invalid_category}
        end

      :error ->
        {:ok, template.category()}
    end
  end

  defp live(:transactional, organization_id) when is_binary(organization_id) do
    case Organizations.get_by_id(organization_id) do
      nil ->
        {:error, :not_live}

      organization ->
        case Organizations.go_live(organization, :send_outside) do
          :ok -> :ok
          {:error, _reason} -> {:error, :not_live}
        end
    end
  end

  defp live(_category, _organization_id), do: :ok

  defp existing(_store, nil), do: nil
  defp existing(store, key) when is_binary(key), do: store.get_by_idempotency_key(key)

  defp not_suppressed(store, address),
    do: if(store.suppressed?(Address.digest(address)), do: {:error, :suppressed}, else: :ok)

  defp throttle(store, template, kind, address, category, now) do
    rule =
      if function_exported?(template, :throttle, 0),
        do: template.throttle(),
        else: SendingPolicy.default_throttle(category)

    recent = store.recent_to(address, kind_name(kind), DateTime.add(now, -@day_seconds, :second))
    SendingPolicy.throttle(rule, recent, now)
  end

  defp budget(store, category, now) do
    sent_today = store.count_sent_since(SendingPolicy.day_start(now))

    case SendingPolicy.on_enqueue(category, sent_today, Palee.Email.budget(), now) do
      :queue -> {:ok, :now}
      {:defer, until} -> {:ok, {:deferred, until}}
      {:error, _reason} = refused -> refused
    end
  end

  defp insert(store, template, kind, address, assigns, category, schedule, opts) do
    locale = Keyword.get(opts, :locale) || "en"
    assigns = Map.new(assigns)

    body =
      Jason.encode!(%{
        "text" => template.text(assigns, locale),
        "html" => template.html(assigns, locale)
      })

    {status, scheduled_at} =
      case schedule do
        :now -> {"queued", nil}
        {:deferred, until} -> {"deferred", until}
      end

    attrs = %{
      kind: kind_name(kind),
      to_address: address,
      login_id: Keyword.get(opts, :login_id),
      user_id: Keyword.get(opts, :user_id),
      organization_id: Keyword.get(opts, :organization_id),
      locale: locale,
      category: Atom.to_string(category),
      subject: single_line(template.subject(assigns, locale)),
      encrypted_body: DataCipher.encrypt(body),
      status: status,
      message_id: Palee.Email.new_message_id(),
      idempotency_key: Keyword.get(opts, :idempotency_key),
      scheduled_at: scheduled_at
    }

    job = fn message ->
      job_opts = if scheduled_at, do: [scheduled_at: scheduled_at], else: []
      DeliverEmailJob.new(%{"message_id" => message.id}, job_opts)
    end

    with {:ok, message} <- store.insert_with_job(attrs, job) do
      Palee.Email.emit(:enqueued, message)
      if message.status == "deferred", do: Palee.Email.emit(:deferred, message)
      {:ok, message}
    end
  end

  defp kind_name(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp kind_name(kind) when is_binary(kind), do: kind

  # A subject is a header: no line breaks, whatever the assigns held.
  defp single_line(subject), do: subject |> to_string() |> String.replace(~r/[\r\n]+/, " ")
end
