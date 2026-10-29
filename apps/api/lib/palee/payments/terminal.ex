defmodule Palee.Payments.Terminal do
  @moduledoc """
  Tap to Pay at the desk (ADR-249): staff take a card on their phone
  through the provider's terminal app, and Palee records the money only
  after the provider confirmed it.

  A terminal payment is a payment intent (`initiation: "terminal"`), so
  the payments worker (`Payments.process/3`) settles, polls and fulfils
  it like every other intent; this module opens it, reads what the phone
  reports, and tells the worker what the provider says.
  """

  alias Palee.Payments
  alias Palee.Payments.PaymentStore
  alias Palee.Payments.Domain.{TerminalPolicy, TipAttribution}

  @doc false
  def gateway(provider) do
    :palee
    |> Application.get_env(:payment_terminals, %{})
    |> Map.get(provider)
  end

  defp app_settings, do: Application.get_env(:palee, :payment_terminal_app, [])

  defp sandbox_enabled?, do: Application.get_env(:palee, :payments_sandbox, false) == true

  @doc "Whether the business can take Tap to Pay now (an active account whose provider has a terminal app)."
  def available?(context), do: match?({:ok, _account}, terminal_account(context))

  @doc """
  ADR-272: whether the business can take Tap to Pay now and, when not, why:
  `no_viva` (no payment account), `stripe_only` (its provider is Stripe,
  which has no terminal app in Palee), `provider_without_terminal` (another
  provider without one) or `account_not_ready` (the account is not active).
  Whether the phone has the terminal app is only known on the phone.
  """
  def availability(context) do
    account = PaymentStore.get_account(context)

    reason =
      case {account, terminal_account(context)} do
        {_account, {:ok, _ready}} -> nil
        {nil, _error} -> "no_viva"
        {%{provider: "stripe"}, _error} -> "stripe_only"
        {%{status: "active"}, _error} -> "provider_without_terminal"
        {%{provider: provider}, _error} -> if gateway(provider), do: "account_not_ready", else: "provider_without_terminal"
      end

    %{
      available: is_nil(reason),
      reason: reason,
      provider: account && account.provider
    }
  end

  defp terminal_account(context) do
    case PaymentStore.get_account(context) do
      %{status: "active", provider: "sandbox"} = account ->
        if sandbox_enabled?(), do: {:ok, account}, else: {:error, :terminal_payments_unavailable}

      %{status: "active", provider: provider} = account ->
        if gateway(provider), do: {:ok, account}, else: {:error, :terminal_payments_unavailable}

      _other ->
        {:error, :terminal_payments_unavailable}
    end
  end

  # ── Start ───────────────────────────────────────────────────────────────

  @doc """
  Opens a terminal payment and returns it with the request the phone hands
  to the terminal app. `request`: purpose_type, purpose_id, user_id (nil
  for a walk-in), amount_cents, currency, description, idempotency_key,
  created_by_id, metadata. A retry with the same key returns the first one.
  """
  def start(context, request, %DateTime{} = now) do
    with :ok <- TerminalPolicy.validate_new(request) do
      case PaymentStore.get_intent_by_key(context, request.idempotency_key) do
        %{initiation: "terminal"} = existing -> {:ok, present(existing, now)}
        %{} -> {:error, :duplicate_idempotency_key}
        nil -> new_payment(context, request, now)
      end
    end
  end

  defp new_payment(context, request, now) do
    expires_at = DateTime.add(now, TerminalPolicy.request_ttl_seconds(), :second)

    with {:ok, account} <- terminal_account(context),
         {:ok, intent} <-
           PaymentStore.insert_intent(context, %{
             organization_id: context.organization_id,
             account_id: account.id,
             provider: account.provider,
             environment: account.environment,
             user_id: request[:user_id],
             initiation: "terminal",
             purpose_type: request.purpose_type,
             purpose_id: request.purpose_id,
             amount_cents: request.amount_cents,
             currency: request.currency,
             description: Payments.Domain.IntentPolicy.description(request[:description]),
             status: "awaiting_payer",
             idempotency_key: request.idempotency_key,
             metadata: request[:metadata] || %{},
             expires_at: expires_at,
             next_attempt_at: DateTime.add(expires_at, 60, :second),
             created_by_id: request[:created_by_id]
           }) do
      {:ok, present(intent, now)}
    else
      {:error, :duplicate_idempotency_key} ->
        case PaymentStore.get_intent_by_key(context, request.idempotency_key) do
          %{initiation: "terminal"} = intent -> {:ok, present(intent, now)}
          _other -> {:error, :duplicate_idempotency_key}
        end

      error ->
        error
    end
  end

  # ── Result from the phone ───────────────────────────────────────────────

  @doc """
  What the terminal app returned through the phone (`reference`,
  `status`, `transaction_id`, `message`). A transaction is confirmed with
  the provider before anything is recorded; a duplicate callback answers
  the payment as it stands.
  """
  def record_result(context, params, %DateTime{} = now) do
    with {:ok, intent} <- by_reference(context, params[:reference]) do
      device = TerminalPolicy.device_result(params)

      case TerminalPolicy.apply_device(intent, device, now) do
        {:confirm, changes} ->
          with :ok <- transaction_free(context, intent, changes.provider_transaction_id),
               {:ok, _updated} <- PaymentStore.update_intent(context, intent.id, changes) do
            Payments.process(context, intent.id, now)
            {:ok, context |> PaymentStore.get_intent(intent.id) |> present(now)}
          end

        {:close, changes} ->
          with {:ok, updated} <- PaymentStore.update_intent(context, intent.id, changes) do
            {:ok, present(updated, now)}
          end

        :unchanged ->
          {:ok, present(intent, now)}

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp by_reference(context, reference) do
    with {:ok, id} <- TerminalPolicy.reference_intent_id(reference),
         %{initiation: "terminal"} = intent <- PaymentStore.get_intent(context, id),
         true <- TerminalPolicy.valid_reference?(reference, intent, key()) do
      {:ok, intent}
    else
      _invalid -> {:error, :not_found}
    end
  end

  # One provider transaction pays one request.
  defp transaction_free(context, intent, transaction_id) do
    case PaymentStore.get_intent_by_ref(context, intent.provider, transaction_id) do
      %{id: id} when id != intent.id -> {:error, :terminal_transaction_used}
      _free -> :ok
    end
  end

  @doc "A terminal payment named by its reference (a webhook's merchant reference), if still open."
  def open_by_reference(context, reference) do
    case by_reference(context, reference) do
      {:ok, %{status: "awaiting_payer"} = intent} -> intent
      _other -> nil
    end
  end

  # ── Worker ──────────────────────────────────────────────────────────────

  @doc """
  Called by the payments worker for a leased terminal intent: confirms its
  transaction with the provider, or looks for a result that never came.
  Returns the changes to write.
  """
  def check(context, account, intent, %DateTime{} = now) do
    gateway = gateway(account.provider)
    reference = TerminalPolicy.reference(intent, key())

    cond do
      is_nil(gateway) ->
        TerminalPolicy.confirm_outcome(
          intent,
          {:error, {:invalid, :no_terminal}},
          reference,
          now
        )

      is_binary(intent.provider_transaction_id) ->
        result = gateway.confirm(account, intent.provider_transaction_id)
        confirmed(context, intent, result, reference, now)

      TerminalPolicy.too_early_to_look?(intent, now) ->
        %{next_attempt_at: TerminalPolicy.first_lookup_at(intent), claimed_at: nil}

      true ->
        case find(gateway, account, reference, intent.inserted_at) do
          {:ok, %{transaction_id: id} = transaction} when is_binary(id) ->
            found = %{intent | provider_transaction_id: id}

            context
            |> confirmed(found, {:ok, transaction}, reference, now)
            |> Map.put_new(:provider_transaction_id, id)

          result ->
            TerminalPolicy.lost_outcome(intent, result, now)
        end
    end
  end

  defp confirmed(context, intent, {:ok, %{status: :succeeded}} = result, reference, now) do
    case transaction_free(context, intent, intent.provider_transaction_id) do
      :ok ->
        TerminalPolicy.confirm_outcome(intent, result, reference, now)

      {:error, _used} ->
        %{
          status: "failed",
          next_attempt_at: nil,
          claimed_at: nil,
          failure_code: "terminal_transaction_used",
          attempts: (intent.attempts || 0) + 1
        }
    end
  end

  defp confirmed(_context, intent, result, reference, now),
    do: TerminalPolicy.confirm_outcome(intent, result, reference, now)

  # The provider's day may be the business's local day: look on the UTC
  # day of the request and on the day a few hours later.
  defp find(gateway, account, reference, requested_at) do
    [requested_at, DateTime.add(requested_at, 3 * 3_600, :second)]
    |> Enum.map(&DateTime.to_date/1)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, nil}, fn date, _acc ->
      case gateway.find_by_reference(account, reference, date) do
        {:ok, nil} = none -> {:cont, none}
        other -> {:halt, other}
      end
    end)
  end

  # ── Staff ───────────────────────────────────────────────────────────────

  @doc "Staff give up on a terminal payment that has no transaction (nothing was paid)."
  def cancel(context, intent_id, %DateTime{} = now) do
    case PaymentStore.get_intent(context, intent_id) do
      %{initiation: "terminal", status: "awaiting_payer", provider_transaction_id: nil} = intent ->
        with {:ok, updated} <-
               PaymentStore.update_intent(context, intent.id, %{
                 status: "cancelled",
                 next_attempt_at: nil,
                 claimed_at: nil,
                 failure_code: "terminal_cancelled_by_staff"
               }) do
          {:ok, present(updated, now)}
        end

      %{initiation: "terminal"} ->
        {:error, :payment_not_cancellable}

      _other ->
        {:error, :not_found}
    end
  end

  def get(context, intent_id, %DateTime{} = now) do
    case PaymentStore.get_intent(context, intent_id) do
      %{initiation: "terminal"} = intent -> {:ok, present(intent, now)}
      _other -> {:error, :not_found}
    end
  end

  @doc """
  Dev/test only: the transaction id the sandbox terminal app would return
  for this payment (`outcome`: succeeded, failed, cancelled). ADR-264:
  `extras` (`tip_cents`, `surcharge_cents`, `amount_cents`) as
  `SandboxTerminalGateway.complete/4`.
  """
  def sandbox_transaction(context, intent_id, outcome, extras \\ %{}) do
    with true <- sandbox_enabled?() || {:error, :not_found},
         %{initiation: "terminal", provider: "sandbox"} = intent <-
           PaymentStore.get_intent(context, intent_id) || {:error, :not_found} do
      reference = TerminalPolicy.reference(intent, key())

      {:ok, reference,
       gateway("sandbox").complete(reference, outcome, intent.amount_cents, extras)}
    else
      %{} -> {:error, :not_found}
      error -> error
    end
  end

  # ── Presenting ──────────────────────────────────────────────────────────

  @doc """
  The payment as staff and the phone see it: the intent, its reference
  and, while the phone may still launch it, the terminal app request.
  """
  def present(intent, now) do
    reference = TerminalPolicy.reference(intent, key())

    intent
    |> Payments.public_intent()
    |> Map.merge(%{
      reference: reference,
      tip_cents: intent.tip_cents || 0,
      surcharge_cents: intent.surcharge_cents || 0,
      expires_at: intent.expires_at,
      failure_message: intent.failure_message,
      app_request: app_request(intent, reference, now),
      # ADR-272: the payment's receipt, and whose tip it is.
      fiscal_document_id: intent[:fiscal_document_id],
      started_by_id: intent[:created_by_id],
      started_on: TipAttribution.started_on(intent),
      tip_attribution: intent[:tip_attribution],
      tip_recipient_user_id: intent[:tip_recipient_user_id],
      tip_recipient_role: intent[:tip_recipient_role]
    })
  end

  defp app_request(intent, reference, now) do
    with true <- TerminalPolicy.launchable?(intent, now),
         gateway when not is_nil(gateway) <- gateway(intent.provider) do
      settings = app_settings()

      request =
        gateway.app_request(%{provider: intent.provider, environment: intent.environment}, %{
          reference: reference,
          amount_cents: intent.amount_cents,
          currency: intent.currency,
          description: intent.description,
          app_id: Keyword.get(settings, :app_id, "app.palee.member"),
          callback: Keyword.get(settings, :callback, "palee-terminal://result")
        })

      Map.put(request, :url, request.scheme <> "?" <> URI.encode_query(request.params, :rfc3986))
    else
      _not_launchable -> nil
    end
  end

  # The key that signs references: its own secret when configured,
  # otherwise derived from the endpoint secret.
  defp key do
    case Application.get_env(:palee, :payment_terminal_secret) do
      secret when is_binary(secret) and byte_size(secret) >= 32 ->
        secret

      _none ->
        base =
          :palee
          |> Application.get_env(PaleeWeb.Endpoint, [])
          |> Keyword.get(:secret_key_base, "palee-dev-terminal")

        :crypto.mac(:hmac, :sha256, base, "palee-payment-terminal-references")
    end
  end
end
