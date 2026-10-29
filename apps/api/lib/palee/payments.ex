defmodule Palee.Payments do
  @moduledoc """
  Online payments (ADR-246/247): the business's own provider account
  (Viva, Stripe, or the sandbox in dev and test), payer checkouts on the
  provider's page, saved cards charged within the payer's consent, refunds,
  and webhooks that only tell us to ask the provider again.

  Provider calls never run inside a database transaction. An intent is
  leased (`claimed_at`) while one worker talks to the provider, so two
  workers never charge the same intent.
  """

  alias Palee.Payments.PaymentStore
  alias Palee.Payments.Domain.{AccountOptions, Consent, IntentPolicy}

  @providers ~w(sandbox viva stripe)
  @environments ~w(test live)
  @batch 25
  @max_credential_length 500

  def providers, do: @providers
  def environments, do: @environments

  @doc false
  def gateway(provider) do
    :palee
    |> Application.get_env(:payment_gateways, %{})
    |> Map.fetch!(provider)
  end

  defp fulfilment, do: Application.fetch_env!(:palee, :payment_fulfilment)

  defp sandbox_enabled?, do: Application.get_env(:palee, :payments_sandbox, false) == true

  # ── Account ─────────────────────────────────────────────────────────────

  @doc "The business's provider account, without its credentials."
  def account(context), do: context |> PaymentStore.get_account() |> public_account()

  @doc "Whether the business can take online payments now."
  def available?(context) do
    case PaymentStore.get_account(context) do
      %{status: "active", provider: "sandbox"} -> sandbox_enabled?()
      %{status: "active"} -> true
      _other -> false
    end
  end

  @doc """
  Whether members may pay `purpose` online now (ADR-260): the account is
  active and the business left that purpose on.
  """
  def available?(context, purpose) do
    case PaymentStore.get_account(context) do
      %{status: "active"} = account ->
        available?(context) and AccountOptions.allows?(account.options || %{}, purpose)

      _other ->
        false
    end
  end

  @doc "Changes what members pay online and who hears about failed charges."
  def save_options(context, params, actor_id, %DateTime{} = _now) do
    with %{} = account <-
           PaymentStore.get_account(context) || {:error, :online_payments_unavailable},
         {:ok, options} <- AccountOptions.change(account.options || %{}, params),
         {:ok, saved} <-
           PaymentStore.save_account(context, %{options: options, updated_by_id: actor_id}) do
      {:ok, public_account(saved)}
    end
  end

  @doc """
  Saves the provider account after the provider accepted its credentials.
  Secrets left out keep their saved values (when the provider is the same).
  """
  def save_account(context, params, actor_id, %DateTime{} = now) do
    provider = params[:provider] || params["provider"]
    environment = params[:environment] || params["environment"]

    with :ok <- validate_choice(provider, @providers, :provider),
         :ok <- validate_choice(environment, @environments, :environment),
         :ok <- sandbox_rules(provider, environment),
         current = PaymentStore.get_account(context),
         gateway = gateway(provider),
         {:ok, credentials} <- merge_credentials(gateway, current, provider, params),
         settings = settings(gateway, params),
         candidate = %{
           provider: provider,
           environment: environment,
           credentials: credentials,
           settings: settings
         },
         :ok <- check_with_provider(gateway, candidate),
         {:ok, saved} <-
           PaymentStore.save_account(
             context,
             Map.merge(candidate, %{
               status: "active",
               last_error: nil,
               checked_at: now,
               updated_by_id: actor_id
             })
           ) do
      {:ok, public_account(saved)}
    end
  end

  # ── One-button connection (ADR-261) ────────────────────────────────────

  defp connector(provider),
    do: :palee |> Application.get_env(:payment_connect, %{}) |> Map.get(provider)

  @doc "Providers a business can connect with one button in `environment`."
  def connect_providers(environment) do
    Enum.filter(@providers, fn provider ->
      case connector(provider) do
        nil -> false
        module -> module.available?(environment)
      end
    end)
  end

  @doc "The provider page where the owner allows Palee (see `Ports.Connect`)."
  def connect_url(provider, environment, request) do
    with :ok <- validate_choice(environment, @environments, :environment),
         true <- provider in connect_providers(environment) || {:error, :connect_not_available} do
      connector(provider).authorize_url(environment, request)
    end
  end

  @doc """
  Finishes a one-button connection: the provider's answer becomes the
  business's account, checked with a harmless call like pasted keys.
  """
  def complete_connect(context, provider, environment, params, actor_id, %DateTime{} = now) do
    with true <-
           provider in connect_providers(environment) || {:error, :connect_not_available},
         {:ok, %{connected_account: connected}} <-
           connector(provider).complete(environment, params),
         candidate = %{
           provider: provider,
           environment: environment,
           credentials: %{"connected_account" => connected},
           settings: %{"connection" => "platform"}
         },
         :ok <- check_with_provider(gateway(provider), candidate),
         {:ok, saved} <-
           PaymentStore.save_account(
             context,
             Map.merge(candidate, %{
               status: "active",
               last_error: nil,
               checked_at: now,
               updated_by_id: actor_id
             })
           ) do
      {:ok, public_account(saved)}
    end
  end

  @doc """
  Stops online payments: the account is disabled (saved cards are no
  longer charged) and, for a one-button connection, Palee's access at the
  provider is removed. Reconnecting brings the same saved cards back.
  """
  def disconnect(context, actor_id, %DateTime{} = now) do
    with %{} = account <-
           PaymentStore.get_account(context) || {:error, :online_payments_unavailable} do
      case {connector(account.provider), account.credentials} do
        {module, %{"connected_account" => connected}} when not is_nil(module) ->
          module.disconnect(account.environment, connected)

        _keys ->
          :ok
      end
      |> case do
        :ok ->
          {:ok, saved} =
            PaymentStore.save_account(context, %{
              status: "disabled",
              checked_at: now,
              updated_by_id: actor_id
            })

          {:ok, public_account(saved)}

        {:error, _reason} ->
          {:error, :payment_provider_unavailable}
      end
    end
  end

  defp validate_choice(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_fields, %{field => "invalid"}}}
  end

  defp sandbox_rules("sandbox", environment) do
    cond do
      not sandbox_enabled?() -> {:error, {:invalid_fields, %{provider: "unavailable"}}}
      environment != "test" -> {:error, {:invalid_fields, %{environment: "invalid"}}}
      true -> :ok
    end
  end

  defp sandbox_rules(_provider, _environment), do: :ok

  defp merge_credentials(gateway, current, provider, params) do
    given = params[:credentials] || params["credentials"] || %{}

    saved =
      case current do
        %{provider: ^provider, credentials: credentials} -> credentials
        _other -> %{}
      end

    {merged, errors} =
      Enum.reduce(gateway.credential_keys(), {%{}, %{}}, fn key, {acc, errors} ->
        value =
          case given[key] || given[String.to_existing_atom(key)] do
            value when is_binary(value) and value != "" -> String.trim(value)
            _missing -> saved[key]
          end

        cond do
          not is_binary(value) or value == "" ->
            {acc, Map.put(errors, key, "required")}

          byte_size(value) > @max_credential_length ->
            {acc, Map.put(errors, key, "too_long")}

          true ->
            {Map.put(acc, key, value), errors}
        end
      end)

    if errors == %{},
      do: {:ok, merged},
      else: {:error, {:invalid_fields, errors}}
  end

  defp settings(gateway, params) do
    given = params[:settings] || params["settings"] || %{}

    Map.new(gateway.setting_keys(), fn key ->
      value = given[key] || given[String.to_existing_atom(key)]
      {key, if(is_binary(value), do: value |> String.trim() |> String.slice(0, 100))}
    end)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp check_with_provider(gateway, account) do
    case gateway.check(account) do
      :ok ->
        :ok

      {:error, {:unauthorized, _}} ->
        {:error, {:invalid_fields, %{credentials: "rejected"}}}

      {:error, {:invalid, :key_mode_mismatch}} ->
        {:error, {:invalid_fields, %{environment: "mismatch"}}}

      {:error, {:invalid, :sandbox_disabled}} ->
        {:error, {:invalid_fields, %{provider: "unavailable"}}}

      {:error, _other} ->
        {:error, :payment_provider_unavailable}
    end
  end

  defp public_account(nil), do: nil

  defp public_account(account) do
    account
    |> Map.take([
      :id,
      :provider,
      :environment,
      :status,
      :settings,
      :last_error,
      :checked_at,
      :updated_at
    ])
    |> Map.put(:credentials_set, (account.credentials || %{}) |> Map.keys() |> Enum.sort())
    |> Map.put(:options, AccountOptions.resolve(account[:options] || %{}))
    |> Map.put(:connection, connection(account))
  end

  defp connection(%{settings: %{"connection" => "platform"}}), do: "platform"
  defp connection(_account), do: "keys"

  defp active_account(context) do
    case PaymentStore.get_account(context) do
      %{status: "active", provider: "sandbox"} = account ->
        if sandbox_enabled?(), do: {:ok, account}, else: {:error, :online_payments_unavailable}

      %{status: "active"} = account ->
        {:ok, account}

      _other ->
        {:error, :online_payments_unavailable}
    end
  end

  # ── Payer checkout ──────────────────────────────────────────────────────

  @doc """
  Opens a checkout on the provider's page. `request`: purpose_type,
  purpose_id, user_id, amount_cents, currency, description, customer
  (email, name, language), return_url and cancel_url (may contain
  `{payment_id}`), save_method, consent (accepted, ip, user_agent,
  language), consent_terms (business, purpose, max_amount_cents),
  idempotency_key, created_by_id.
  """
  def start_checkout(context, request, %DateTime{} = now) do
    with :ok <- IntentPolicy.validate_new(request) do
      case PaymentStore.get_intent_by_key(context, request.idempotency_key) do
        %{} = existing -> {:ok, public_intent(existing)}
        nil -> new_checkout(context, request, now)
      end
    end
  end

  defp new_checkout(context, request, now) do
    with {:ok, account} <- active_account(context),
         {:ok, consent} <- checkout_consent(request, now),
         {:ok, intent} <-
           PaymentStore.insert_intent(context, %{
             organization_id: context.organization_id,
             account_id: account.id,
             provider: account.provider,
             environment: account.environment,
             user_id: request[:user_id],
             initiation: "payer",
             purpose_type: request.purpose_type,
             purpose_id: request.purpose_id,
             amount_cents: request.amount_cents,
             currency: request.currency,
             description: IntentPolicy.description(request[:description]),
             status: "awaiting_payer",
             idempotency_key: request.idempotency_key,
             save_method: consent != nil,
             consent: consent,
             metadata: request[:metadata] || %{},
             expires_at: DateTime.add(now, IntentPolicy.checkout_ttl_seconds(), :second),
             next_attempt_at: DateTime.add(now, 120, :second),
             claimed_at: now,
             created_by_id: request[:created_by_id]
           }) do
      open_checkout(context, account, intent, request)
    else
      {:error, :duplicate_idempotency_key} -> retry_lookup(context, request.idempotency_key)
      error -> error
    end
  end

  defp checkout_consent(%{save_method: true} = request, now) do
    terms = Map.put(request[:consent_terms] || %{}, :currency, request.currency)
    Consent.record(request[:consent] || %{}, terms, now)
  end

  defp checkout_consent(_request, _now), do: {:ok, nil}

  defp retry_lookup(context, key) do
    case PaymentStore.get_intent_by_key(context, key) do
      %{} = intent -> {:ok, public_intent(intent)}
      nil -> {:error, :duplicate_idempotency_key}
    end
  end

  defp open_checkout(context, account, intent, request) do
    url = fn template -> String.replace(template || "", "{payment_id}", intent.id) end

    checkout = %{
      reference: intent.id,
      amount_cents: intent.amount_cents,
      currency: intent.currency,
      description: intent.description,
      customer: request[:customer] || %{},
      save_method: intent.save_method,
      return_url: url.(request[:return_url]),
      cancel_url: url.(request[:cancel_url] || request[:return_url]),
      expires_at: intent.expires_at,
      idempotency_key: "palee-checkout-" <> intent.id
    }

    case gateway(account.provider).create_checkout(account, checkout) do
      {:ok, %{provider_ref: ref, redirect_url: redirect}} ->
        {:ok, updated} =
          PaymentStore.update_intent(context, intent.id, %{
            provider_ref: ref,
            redirect_url: redirect,
            return_url: checkout.return_url,
            claimed_at: nil
          })

        {:ok, public_intent(updated)}

      {:error, reason} ->
        PaymentStore.update_intent(context, intent.id, %{
          status: "failed",
          next_attempt_at: nil,
          claimed_at: nil,
          failure_code: "checkout_not_opened",
          failure_message: reason |> inspect() |> String.slice(0, 500)
        })

        provider_error(reason)
    end
  end

  defp provider_error({:unauthorized, _}), do: {:error, :payment_provider_rejected_credentials}
  defp provider_error({:declined, _code, _message}), do: {:error, :payment_declined}
  defp provider_error(_reason), do: {:error, :payment_provider_unavailable}

  # ── Saved-card charge ───────────────────────────────────────────────────

  @doc """
  Charges a saved card without the payer, within their consent.
  `request`: payment_method_id plus the fields of `start_checkout/3`
  (without customer, URLs and consent).
  """
  def charge_saved(context, request, %DateTime{} = now) do
    with :ok <- IntentPolicy.validate_new(request) do
      case PaymentStore.get_intent_by_key(context, request.idempotency_key) do
        %{} = existing -> {:ok, public_intent(existing)}
        nil -> new_charge(context, request, now)
      end
    end
  end

  defp new_charge(context, request, now) do
    with {:ok, account} <- active_account(context),
         %{} = method <-
           PaymentStore.get_method(context, request.payment_method_id) || {:error, :not_found},
         true <- method.account_id == account.id || {:error, :payment_method_inactive},
         :ok <-
           Consent.allows?(method, request.amount_cents, request.currency, DateTime.to_date(now)),
         {:ok, intent} <-
           PaymentStore.insert_intent(context, %{
             organization_id: context.organization_id,
             account_id: account.id,
             provider: account.provider,
             environment: account.environment,
             user_id: method.user_id,
             initiation: "merchant",
             purpose_type: request.purpose_type,
             purpose_id: request.purpose_id,
             amount_cents: request.amount_cents,
             currency: request.currency,
             description: IntentPolicy.description(request[:description]),
             status: "scheduled",
             idempotency_key: request.idempotency_key,
             payment_method_id: method.id,
             consent: %{"declines" => 0},
             next_attempt_at: now,
             created_by_id: request[:created_by_id]
           }) do
      process(context, intent.id, now)
      {:ok, context |> PaymentStore.get_intent(intent.id) |> public_intent()}
    else
      {:error, :duplicate_idempotency_key} -> retry_lookup(context, request.idempotency_key)
      error -> error
    end
  end

  # ── Settling ────────────────────────────────────────────────────────────

  @doc """
  Advances due intents (or one intent): asks the provider, charges
  scheduled saved cards, then fulfils succeeded payments.
  """
  def process(context, which \\ :due, %DateTime{} = now) do
    advanced =
      context
      |> PaymentStore.claim_due(which, now, @batch)
      |> Enum.map(&advance(context, &1, now))

    fulfilled =
      context
      |> PaymentStore.claim_fulfilments(which, now, @batch)
      |> Enum.map(&fulfil(context, &1, now))

    Enum.frequencies(advanced ++ fulfilled)
    |> then(
      &Map.merge(%{succeeded: 0, failed: 0, waiting: 0, fulfilled: 0, fulfilment_failed: 0}, &1)
    )
  end

  @doc "Asks the provider about one intent now (return page, webhook, staff retry)."
  def refresh(context, intent_id, transaction_id \\ nil, %DateTime{} = now) do
    case PaymentStore.get_intent(context, intent_id) do
      nil ->
        {:error, :not_found}

      intent ->
        if is_binary(transaction_id) and transaction_id != "" and IntentPolicy.open?(intent) and
             is_nil(intent.provider_transaction_id) do
          PaymentStore.update_intent(context, intent.id, %{
            provider_transaction_id: String.slice(transaction_id, 0, 200),
            next_attempt_at: now
          })
        else
          if IntentPolicy.open?(intent),
            do: PaymentStore.update_intent(context, intent.id, %{next_attempt_at: now})
        end

        process(context, intent.id, now)
        {:ok, context |> PaymentStore.get_intent(intent.id) |> public_intent()}
    end
  end

  defp advance(context, intent, now) do
    case PaymentStore.get_account(context, intent.account_id) do
      nil ->
        PaymentStore.update_intent(context, intent.id, %{
          claimed_at: nil,
          next_attempt_at: DateTime.add(now, 3_600, :second)
        })

        :waiting

      account ->
        changes =
          cond do
            # ADR-249: a card tapped on the provider's terminal app.
            intent.initiation == "terminal" ->
              Palee.Payments.Terminal.check(context, account, intent, now)

            intent.initiation == "merchant" and intent.status == "scheduled" ->
              charge(context, account, intent, now)

            true ->
              check_checkout(account, intent, now)
          end

        {:ok, updated} = apply_outcome(context, account, intent, changes)
        notify_decline(context, account, intent, updated)
        finish(intent, updated)
    end
  end

  # ADR-260: a declined saved-card charge (not a provider outage) is told to
  # the member each time, and to staff once no retry is left.
  defp notify_decline(context, account, %{initiation: "merchant"} = before, updated) do
    declined? = declines(updated) > declines(before)
    final? = updated.status == "failed"

    if declined? or final? do
      notifier().charge_declined(context, updated, %{
        final: final?,
        options: account[:options] || %{}
      })
    end

    :ok
  end

  defp notify_decline(_context, _account, _intent, _updated), do: :ok

  defp declines(intent), do: Map.get(intent.consent || %{}, "declines", 0)

  defp charge(context, account, intent, now) do
    case intent.payment_method_id && PaymentStore.get_method(context, intent.payment_method_id) do
      %{status: "active", token: token} when is_binary(token) ->
        result =
          gateway(account.provider).charge_saved(account, token, %{
            reference: intent.id,
            amount_cents: intent.amount_cents,
            currency: intent.currency,
            description: intent.description,
            idempotency_key: "palee-charge-#{intent.id}-#{intent.attempts}"
          })

        result
        |> guard_amount(intent)
        |> then(&IntentPolicy.charge_outcome(intent, &1, now))

      _missing ->
        %{
          status: "failed",
          next_attempt_at: nil,
          claimed_at: nil,
          failure_code: "payment_method_not_found",
          attempts: intent.attempts + 1
        }
    end
  end

  defp check_checkout(account, intent, now) do
    result =
      if intent.provider_ref || intent.provider_transaction_id do
        gateway(account.provider).fetch_payment(account, %{
          provider_ref: intent.provider_ref,
          transaction_id: intent.provider_transaction_id
        })
      else
        {:error, {:transient, :checkout_not_opened}}
      end

    result = guard_amount(result, intent)

    intent
    |> IntentPolicy.checkout_outcome(result, now)
    |> with_details(result)
  end

  # The token and card details go to the saved card, not to the intent.
  defp with_details(%{status: "succeeded"} = changes, {:ok, payment}),
    do: Map.put(changes, :details, %{method_token: payment[:method_token], card: payment[:card]})

  defp with_details(changes, _result), do: changes

  # A provider that reports another amount or currency than we asked for
  # is never treated as paid.
  defp guard_amount({:ok, %{status: :succeeded} = payment} = result, intent) do
    if IntentPolicy.amount_mismatch?(intent, payment),
      do:
        {:ok,
         %{payment | status: :failed}
         |> Map.put(:failure, %{code: "amount_mismatch", message: nil})},
      else: result
  end

  defp guard_amount(result, _intent), do: result

  defp apply_outcome(context, account, intent, %{status: "succeeded"} = changes) do
    {details, changes} = Map.pop(changes, :details, %{})

    PaymentStore.transaction(context, fn ->
      method = save_method(context, account, intent, details)

      changes =
        case method do
          %{id: id} -> Map.put(changes, :payment_method_id, id)
          nil -> changes
        end

      PaymentStore.update_intent(context, intent.id, changes)
    end)
  end

  defp apply_outcome(context, _account, intent, changes),
    do: PaymentStore.update_intent(context, intent.id, changes)

  # Keeps the card for later charges when the payer agreed to it.
  defp save_method(
         context,
         account,
         %{save_method: true, consent: %{} = consent} = intent,
         details
       )
       when is_binary(intent.user_id) do
    with token when is_binary(token) <- details[:method_token] do
      card = details[:card] || %{}

      {:ok, method} =
        PaymentStore.upsert_method(context, %{
          account_id: account.id,
          user_id: intent.user_id,
          provider: account.provider,
          token: token,
          token_digest: Consent.hash(account.provider <> ":" <> token),
          brand: card[:brand],
          last4: card[:last4],
          exp_month: card[:exp_month],
          exp_year: card[:exp_year],
          status: "active",
          consent_version: consent["version"],
          consent_text_hash: consent["text_hash"],
          consented_at: parse_time(consent["accepted_at"]),
          consent_ip: consent["ip"],
          consent_user_agent: consent["user_agent"],
          max_amount_cents: consent["max_amount_cents"],
          currency: consent["currency"] || intent.currency
        })

      method
    else
      _none -> nil
    end
  end

  defp save_method(_context, _account, _intent, _changes), do: nil

  defp parse_time(nil), do: nil

  defp parse_time(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      _error -> nil
    end
  end

  defp finish(_intent, %{status: "succeeded"}), do: :succeeded
  defp finish(_intent, %{status: status}) when status in ~w(failed cancelled expired), do: :failed
  defp finish(_intent, _updated), do: :waiting

  defp fulfil(context, intent, now) do
    result =
      try do
        fulfilment().fulfil(context, intent)
      rescue
        error -> {:error, {:exception, Exception.message(error)}}
      end

    changes = IntentPolicy.fulfilment_outcome(intent, result, now)
    PaymentStore.update_intent(context, intent.id, changes)

    if changes.fulfilment_status == "done", do: :fulfilled, else: :fulfilment_failed
  end

  # ── Refunds ─────────────────────────────────────────────────────────────

  @doc "Gives back part or all of a succeeded payment through the provider."
  def refund(context, intent_id, params, actor_id, %DateTime{} = now) do
    key = params[:idempotency_key]
    amount = params[:amount_cents]

    with true <-
           (is_binary(key) and byte_size(key) in 8..200) || {:error, :idempotency_key_required},
         %{} = intent <- PaymentStore.get_intent(context, intent_id) || {:error, :not_found} do
      case PaymentStore.get_refund_by_key(context, key) do
        %{intent_id: ^intent_id} = existing -> {:ok, public_refund(existing)}
        %{} -> {:error, :duplicate_idempotency_key}
        nil -> new_refund(context, intent, amount, key, params[:reason], actor_id, now)
      end
    end
  end

  defp new_refund(context, intent, amount, key, reason, actor_id, now) do
    with :ok <- IntentPolicy.validate_refund(intent, amount),
         {:ok, account} <- refund_account(context, intent),
         {:ok, refund} <-
           PaymentStore.insert_refund(context, %{
             organization_id: context.organization_id,
             intent_id: intent.id,
             amount_cents: amount,
             currency: intent.currency,
             status: "pending",
             reason: reason && String.slice(reason, 0, 300),
             idempotency_key: key,
             created_by_id: actor_id
           }) do
      result =
        gateway(account.provider).refund(account, %{
          transaction_id: intent.provider_transaction_id,
          amount_cents: amount,
          currency: intent.currency,
          idempotency_key: "palee-refund-" <> refund.id
        })

      complete_refund(context, intent, refund, result, now)
    end
  end

  defp refund_account(context, intent) do
    case PaymentStore.get_account(context, intent.account_id) do
      %{} = account -> {:ok, account}
      nil -> {:error, :online_payments_unavailable}
    end
  end

  defp complete_refund(context, intent, refund, {:ok, %{status: status} = result}, now) do
    {:ok, {updated_intent, updated}} =
      PaymentStore.transaction(context, fn ->
        with {:ok, updated_intent} <-
               PaymentStore.add_refunded(context, intent.id, refund.amount_cents),
             {:ok, updated} <-
               PaymentStore.update_refund(context, refund.id, %{
                 status: if(status == :succeeded, do: "succeeded", else: "pending"),
                 provider_ref: result[:provider_ref],
                 completed_at: if(status == :succeeded, do: now)
               }) do
          {:ok, {updated_intent, updated}}
        end
      end)

    updated =
      if updated_intent.fulfilment_status == "done" do
        case fulfilment().reverse(context, updated_intent, updated) do
          {:ok, %{finance_reversal_id: id}} when is_binary(id) ->
            {:ok, refund} =
              PaymentStore.update_refund(context, updated.id, %{finance_reversal_id: id})

            refund

          _other ->
            updated
        end
      else
        updated
      end

    {:ok, public_refund(updated)}
  end

  defp complete_refund(context, _intent, refund, {:error, reason}, now) do
    PaymentStore.update_refund(context, refund.id, %{
      status: "failed",
      failure_message: reason |> inspect() |> String.slice(0, 500),
      completed_at: now
    })

    case provider_error(reason) do
      {:error, :payment_declined} -> {:error, :refund_refused}
      error -> error
    end
  end

  def refunds(context, intent_id),
    do: context |> PaymentStore.list_refunds(intent_id) |> Enum.map(&public_refund/1)

  defp public_refund(refund) do
    Map.take(refund, [
      :id,
      :amount_cents,
      :currency,
      :status,
      :reason,
      :failure_message,
      :completed_at,
      :inserted_at
    ])
  end

  # ── Webhooks ────────────────────────────────────────────────────────────

  @doc """
  Handles a provider's webhook for one account. Events only name a
  payment; each named payment is read back from the provider.
  """
  def handle_webhook(context, account_id, request, %DateTime{} = now) do
    case PaymentStore.get_account(context, account_id) do
      nil ->
        {:error, :not_found}

      account ->
        case gateway(account.provider).parse_webhook(account, Map.put(request, :now, now)) do
          {:ok, events} -> {:ok, Enum.count(events, &webhook_event(context, account, &1, now))}
          other -> other
        end
    end
  end

  defp webhook_event(context, account, event, now) do
    case PaymentStore.record_webhook_event(context, %{
           account_id: account.id,
           provider: account.provider,
           event_id: String.slice(event.event_id, 0, 200),
           event_type: event[:type] && String.slice(event.type, 0, 100),
           reference: event[:provider_ref] || event[:transaction_id],
           received_at: now
         }) do
      {:ok, recorded} ->
        intent =
          (event[:provider_ref] &&
             PaymentStore.get_intent_by_ref(context, account.provider, event.provider_ref)) ||
            (event[:transaction_id] &&
               PaymentStore.get_intent_by_ref(context, account.provider, event.transaction_id)) ||
            (event[:reference] &&
               Palee.Payments.Terminal.open_by_reference(context, event.reference))

        case intent do
          %{} = intent ->
            refresh(context, intent.id, event[:transaction_id], now)
            PaymentStore.finish_webhook_event(context, recorded.id, "processed", nil, now)

          nil ->
            PaymentStore.finish_webhook_event(
              context,
              recorded.id,
              "ignored",
              "no_matching_payment",
              now
            )
        end

        true

      {:duplicate, _event} ->
        false
    end
  end

  # ── Saved cards ─────────────────────────────────────────────────────────

  def methods(context, user_id),
    do: context |> PaymentStore.list_methods(user_id) |> Enum.map(&public_method/1)

  def public_method(method) do
    method
    |> Map.take([
      :id,
      :provider,
      :brand,
      :last4,
      :exp_month,
      :exp_year,
      :status,
      :autopay,
      :max_amount_cents,
      :currency,
      :consented_at,
      :consent_version
    ])
  end

  @doc "The payer (or staff) withdraws the consent: the card is never charged again."
  def revoke_method(context, user_id, method_id, actor_id, %DateTime{} = now) do
    case PaymentStore.get_method(context, method_id) do
      %{user_id: ^user_id} = method ->
        {:ok, updated} =
          PaymentStore.update_method(context, method.id, %{
            status: "revoked",
            autopay: false,
            revoked_at: now,
            revoked_by_id: actor_id
          })

        {:ok, public_method(updated)}

      _other ->
        {:error, :not_found}
    end
  end

  @doc "Turns automatic payment of due invoices on or off for one of the payer's cards."
  def set_autopay(context, user_id, method_id, autopay) when is_boolean(autopay) do
    case PaymentStore.get_method(context, method_id) do
      %{user_id: ^user_id, status: "active"} = method ->
        PaymentStore.transaction(context, fn ->
          if autopay, do: PaymentStore.clear_autopay(context, user_id, method.id)

          case PaymentStore.update_method(context, method.id, %{autopay: autopay}) do
            {:ok, updated} -> {:ok, public_method(updated)}
            error -> error
          end
        end)

      %{user_id: ^user_id} ->
        {:error, :payment_method_inactive}

      _other ->
        {:error, :not_found}
    end
  end

  def autopay_methods(context), do: PaymentStore.autopay_methods(context)

  @doc """
  The sandbox provider's page (dev and test only): the payer pressed pay or
  cancel; returns the transaction id the provider would send back.
  """
  def sandbox_transaction(provider_ref, outcome, decline_card?) do
    if sandbox_enabled?(),
      do: {:ok, gateway("sandbox").complete(provider_ref, outcome, decline_card? == true)},
      else: {:error, :not_found}
  end

  # ── Reading ─────────────────────────────────────────────────────────────

  def get(context, intent_id) do
    case PaymentStore.get_intent(context, intent_id) do
      nil -> {:error, :not_found}
      intent -> {:ok, public_intent(intent)}
    end
  end

  @doc "The intent the business's provider knows by `ref` (a checkout or transaction)."
  def get_by_ref(context, ref) when is_binary(ref) do
    with %{provider: provider} <- PaymentStore.get_account(context),
         %{} = intent <- PaymentStore.get_intent_by_ref(context, provider, ref) do
      {:ok, public_intent(intent)}
    else
      _none -> {:error, :not_found}
    end
  end

  @doc "Whether any payment for this purpose was (partly) given back."
  def refunded?(context, purpose_type, purpose_id) do
    %{intents: intents} =
      PaymentStore.list_intents(context, %{
        purpose_type: purpose_type,
        purpose_id: purpose_id,
        limit: 200
      })

    Enum.any?(intents, &(&1.refunded_cents > 0))
  end

  @doc """
  Saved-card charges that need a person (ADR-260): declined and waiting for
  a retry, or failed for good, until staff close them or the purpose is
  paid online.
  """
  def attention(context, filters \\ %{}) do
    list(context, Map.merge(filters, %{attention: true}))
  end

  @doc "Staff close a failed charge in the queue (e.g. paid at the desk)."
  def dismiss_attention(context, intent_id, actor_id, %DateTime{} = now) do
    with {:ok, intent} <- merchant_intent(context, intent_id),
         {:ok, updated} <-
           PaymentStore.update_intent(context, intent.id, %{
             attention_resolved_at: now,
             attention_resolved_by_id: actor_id,
             attention_resolution: "dismissed",
             # A charge still waiting for a retry stops here too.
             status: if(intent.status == "scheduled", do: "cancelled", else: intent.status),
             next_attempt_at: nil
           }) do
      {:ok, public_intent(updated)}
    end
  end

  @doc """
  Staff try a declined charge once more now. A charge that failed for good
  gets one more attempt; a further decline fails it again without new
  retries.
  """
  def retry_charge(context, intent_id, %DateTime{} = now) do
    with {:ok, intent} <- merchant_intent(context, intent_id),
         true <- intent.status in ["scheduled", "failed"] || {:error, :payment_not_retryable},
         true <- is_nil(intent.attention_resolved_at) || {:error, :payment_not_retryable},
         {:ok, _updated} <-
           PaymentStore.update_intent(context, intent.id, %{
             status: "scheduled",
             next_attempt_at: now,
             consent:
               Map.put(intent.consent || %{}, "declines", length(IntentPolicy.dunning_days()))
           }) do
      process(context, intent.id, now)
      {:ok, context |> PaymentStore.get_intent(intent.id) |> public_intent()}
    end
  end

  @doc "Sends the member again the link to pay with another card."
  def send_card_link(context, intent_id, %DateTime{} = now) do
    with {:ok, intent} <- merchant_intent(context, intent_id),
         true <- is_binary(intent.user_id) || {:error, :not_found} do
      notifier().card_link(context, intent, now)
      {:ok, public_intent(intent)}
    end
  end

  defp merchant_intent(context, intent_id) do
    case PaymentStore.get_intent(context, intent_id) do
      %{initiation: "merchant"} = intent -> {:ok, intent}
      _other -> {:error, :not_found}
    end
  end

  defp notifier, do: Application.fetch_env!(:palee, :payment_notifier)

  def list(context, filters) do
    %{intents: intents, total: total} = PaymentStore.list_intents(context, filters)
    %{payments: Enum.map(intents, &public_intent/1), total: total}
  end

  def public_intent(intent) do
    Map.take(intent, [
      :id,
      :provider,
      :environment,
      :user_id,
      :initiation,
      :purpose_type,
      :purpose_id,
      :amount_cents,
      :currency,
      :description,
      :status,
      :redirect_url,
      :provider_transaction_id,
      :card_brand,
      :card_last4,
      :refunded_cents,
      :failure_code,
      :fulfilment_status,
      :finance_payment_id,
      :expires_at,
      :succeeded_at,
      :next_attempt_at,
      :inserted_at,
      :metadata,
      :attention_resolved_at,
      :attention_resolution
    ])
    |> Map.put(:declines, declines(intent))
    |> Map.put(:retries, length(IntentPolicy.dunning_days()))
  end

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: Palee.Payments.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
