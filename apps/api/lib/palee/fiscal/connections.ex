defmodule Palee.Fiscal.Connections do
  @moduledoc """
  A box's fiscal connections as one set (ADR-273): which ones its country
  asks for, who manages them, and «Δοκιμή σύνδεσης».

  The connections themselves stay where they were saved and used:
  myDATA (`Reporting`, ADR-243), the AADE registry (`Registry`, ADR-265),
  the till devices (`TillSigning`, ADR-251/266) and Peppol
  (`EInvoicing`, ADR-250). This module checks them through their ports
  and records the result on the connection: a stable `error_code`, when
  it was checked and when it is checked next.

  A check runs right after a connection is saved (`:saved`), when staff
  press «Δοκιμή σύνδεσης» (`:manual`, not again within a short interval,
  10 minutes for the registry because each check spends one of the
  business's AADE look-ups), and from the scheduled sweep (`:scheduled`)
  every 3 months, sooner after a failure. A definite refusal marks the
  connection `invalid`; a check that passes brings an `invalid` one back
  and wakes the documents that were waiting for it. The staff who manage
  billing are notified when a connection becomes invalid without anyone
  looking at it (`:scheduled`, or a provider refusing the credentials
  while sending, `mark_invalid/5`).

  Credentials are read here only to be handed to the port; nothing this
  module returns, logs or journals contains them.
  """

  alias Palee.Fiscal.{
    EInvoiceStore,
    EInvoicing,
    FiscalStore,
    Registry,
    Reporting,
    TillSignatureStore,
    TillSigning,
    TransmissionStore
  }

  alias Palee.Fiscal.Domain.{ConnectionCheckPolicy, CountryProfile}

  @authority_keys %{"mydata" => "mydata", "registry" => "gr_registry"}

  def kinds, do: ConnectionCheckPolicy.kinds()

  defp notifier, do: Application.fetch_env!(:palee, :fiscal_connection_notifier)

  # ── What a saved or public connection carries ───────────────────────────

  @doc false
  # Merged into a connection when it is saved: a new save starts afresh.
  def saved_fields,
    do: %{status: "active", last_error: nil, error_code: nil, check_failures: 0}

  @doc false
  # The check result as staff see it. `last_error` (provider text) is never shown.
  def public_check(connection) do
    %{
      error_code: Map.get(connection, :error_code),
      checked_at: Map.get(connection, :checked_at),
      updated_by_id: Map.get(connection, :updated_by_id),
      updated_by_platform: Map.get(connection, :updated_by_platform) == true
    }
  end

  @doc false
  # Journal payloads say when the Palee team saved a connection.
  def platform_mark(payload, params) do
    if Map.get(params, :updated_by_platform) == true,
      do: Map.put(payload, :by_platform, true),
      else: payload
  end

  # ── Who manages them ────────────────────────────────────────────────────

  @doc "`\"owner\"` (the default) or `\"palee\"`."
  def managed_by(context) do
    case FiscalStore.get_connection_setting(context) do
      %{managed_by: managed_by} -> managed_by
      nil -> "owner"
    end
  end

  @doc "The Palee team chooses who manages a box's connections."
  def set_managed_by(context, managed_by, actor_id) do
    FiscalStore.save_connection_setting(context, %{
      managed_by: managed_by,
      updated_by_id: actor_id
    })
  end

  # ── The set ─────────────────────────────────────────────────────────────

  @doc """
  `%{country, kinds, managed_by, connections}`: the kinds the box's
  country asks for (none before a country is chosen) and each one's
  connection as staff see it (nil when not saved yet).
  """
  def overview(context) do
    identity = FiscalStore.get_identity(context)
    country = identity && identity.country_code

    kinds =
      case country && CountryProfile.fetch(country) do
        {:ok, profile} -> ConnectionCheckPolicy.kinds(profile)
        _none -> []
      end

    %{
      country: country,
      kinds: kinds,
      managed_by: managed_by(context),
      connections: Map.new(kinds, &{&1, public(context, &1)})
    }
  end

  @doc "A connection as staff see it, or nil."
  def public(context, "mydata"), do: Reporting.connection(context)
  def public(context, "registry"), do: Registry.connection(context)
  def public(context, "peppol"), do: EInvoicing.connection(context)

  def public(context, kind) when kind in ["tse", "rksv", "sign_fr"],
    do: TillSigning.connection(context, kind)

  # The connection with its credentials, for the port only.
  defp raw(context, kind) when is_map_key(@authority_keys, kind),
    do: TransmissionStore.get_connection(context, Map.fetch!(@authority_keys, kind))

  defp raw(context, "peppol"), do: EInvoiceStore.get_connection(context, EInvoicing.network())

  defp raw(context, kind) when kind in ["tse", "rksv", "sign_fr"],
    do: TillSignatureStore.get_connection(context, kind)

  # ── «Δοκιμή σύνδεσης» ───────────────────────────────────────────────────

  @doc """
  Checks the connection of `kind` and records the result. `source` is
  `:saved`, `:manual` or `:scheduled`; `opts[:today]` is the box's local
  date (the registry look-up's date).

  `{:ok, %{result, error_code, detail, connection}}` where `result` is
  `"ok"`, `"invalid"` or `"unreachable"`, `detail` what the provider said
  that staff may see (the registry: the ΑΦΜ and name AADE has) and
  `connection` the connection as staff see it after the check; or
  `{:error, :unknown_connection | :connection_not_found | :check_too_soon}`.
  """
  def check(context, kind, source, %DateTime{} = now, opts \\ []) do
    with :ok <- known(kind),
         %{} = connection <- raw(context, kind) || {:error, :connection_not_found},
         :ok <- allowed(source, kind, connection, now) do
      answer = run(context, kind, connection, Keyword.get(opts, :today, DateTime.to_date(now)))
      outcome = ConnectionCheckPolicy.outcome(answer)
      changes = changes(connection, outcome, now)

      record(context, kind, changes)
      after_change(context, kind, connection.status, changes, source, now)

      {:ok,
       %{
         result: result(outcome),
         error_code: changes.error_code,
         detail: detail(answer),
         connection: public(context, kind)
       }}
    end
  end

  defp known(kind) do
    if kind in ConnectionCheckPolicy.kinds(), do: :ok, else: {:error, :unknown_connection}
  end

  defp allowed(:manual, kind, connection, now),
    do: ConnectionCheckPolicy.manual_allowed?(kind, connection[:checked_at], now)

  defp allowed(_source, _kind, _connection, _now), do: :ok

  defp run(_context, "mydata", connection, _today), do: Reporting.check_connection(connection)

  defp run(context, "registry", connection, today),
    do: Registry.check_connection(context, connection, today)

  defp run(context, "peppol", connection, _today),
    do: EInvoicing.check_connection(context, connection)

  defp run(_context, _till, connection, _today), do: TillSigning.check_connection(connection)

  # A till device still `provisioning` keeps that status: only saving it
  # again finishes it.
  defp changes(%{status: "provisioning"} = connection, outcome, now) do
    connection
    |> ConnectionCheckPolicy.changes(outcome, now)
    |> Map.delete(:status)
    |> Map.put_new(:error_code, nil)
  end

  defp changes(connection, outcome, now) do
    connection
    |> ConnectionCheckPolicy.changes(outcome, now)
    |> Map.put_new(:error_code, nil)
  end

  defp record(context, kind, changes) when is_map_key(@authority_keys, kind),
    do:
      TransmissionStore.update_connection_check(
        context,
        Map.fetch!(@authority_keys, kind),
        changes
      )

  defp record(context, "peppol", changes),
    do: EInvoiceStore.update_connection_check(context, EInvoicing.network(), changes)

  defp record(context, kind, changes),
    do: TillSignatureStore.update_connection_check(context, kind, changes)

  defp after_change(context, kind, before, changes, source, now) do
    after_status = Map.get(changes, :status, before)

    cond do
      before == "invalid" and after_status == "active" ->
        wake(context, kind, now)

      source == :scheduled and ConnectionCheckPolicy.newly_invalid?(before, after_status) ->
        notifier().connection_failed(context, kind, changes.error_code)

      true ->
        :ok
    end
  end

  defp wake(context, "mydata", now), do: TransmissionStore.wake_waiting(context, now)
  defp wake(_context, "registry", _now), do: 0
  defp wake(context, "peppol", now), do: EInvoiceStore.wake_waiting(context, now)
  defp wake(context, _till, now), do: TillSignatureStore.wake_waiting(context, now)

  defp result(:ok), do: "ok"
  defp result({:invalid, _code}), do: "invalid"
  defp result({:unreachable, _code}), do: "unreachable"

  defp detail({:ok, %{tax_id: tax_id, legal_name: name}}), do: %{tax_id: tax_id, legal_name: name}
  defp detail(_answer), do: %{}

  @doc """
  Marks a connection invalid because the provider refused its credentials
  while working (sending a document, a look-up): `code` for the screens,
  `message` (provider text, no credentials) for support. Notifies the
  staff when it was not invalid already.
  """
  def mark_invalid(context, kind, code, message, %DateTime{} = now) do
    case raw(context, kind) do
      nil ->
        :ok

      connection ->
        changes =
          connection
          |> ConnectionCheckPolicy.changes({:invalid, code}, now)
          |> Map.merge(%{last_error: message && String.slice(message, 0, 500)})

        record(context, kind, changes)

        if ConnectionCheckPolicy.newly_invalid?(connection.status, "invalid"),
          do: notifier().connection_failed(context, kind, code)

        :ok
    end
  end

  @doc """
  The scheduled sweep for one box: checks every connection of its
  country that is due. `{:ok, checked}`.
  """
  def check_due(context, %DateTime{} = now, opts \\ []) do
    %{kinds: kinds} = overview(context)

    checked =
      Enum.count(kinds, fn kind ->
        case raw(context, kind) do
          nil ->
            false

          connection ->
            ConnectionCheckPolicy.due?(connection, now) and
              match?({:ok, _}, check(context, kind, :scheduled, now, opts))
        end
      end)

    {:ok, checked}
  end
end
