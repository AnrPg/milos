defmodule Palee.Application.Fiscal.FiscalConnections do
  @moduledoc """
  Staff, vendor and system use cases of a box's fiscal connections as one
  set (ADR-273, mockup p3): the «Συνδέσεις» card of Στοιχεία τιμολόγησης,
  «Δοκιμή σύνδεσης», who manages the connections, the check that follows
  every save and the scheduled sweep.

  Saving a connection stays with its own use case (`FiscalReporting`,
  `FiscalRegistry`, `FiscalTillSigning`, `FiscalEInvoicing`); each calls
  `guard/2` first and `after_save/3` last. The Palee team saves through
  `save/5` from the vendor console: the same use cases, marked
  `updated_by_platform` and recorded in the platform audit log.
  """

  alias Palee.{Identity, Organizations}
  alias Palee.Application.Fiscal.{FiscalEInvoicing, FiscalRegistry, FiscalReporting}
  alias Palee.Application.Fiscal.FiscalTillSigning
  alias Palee.Fiscal.{ConnectionSetting, Connections}
  alias Palee.Organizations.PlatformContext

  @doc """
  `%{country, kinds, managed_by, connections}` for the «Συνδέσεις» card:
  only the kinds the box's country asks for, each connection with the
  name of whoever saved it last (nil when the Palee team did).
  """
  def overview(context) do
    overview = Connections.overview(context)
    names = names(Map.values(overview.connections))

    Map.update!(overview, :connections, fn connections ->
      Map.new(connections, fn {kind, connection} -> {kind, with_name(connection, names)} end)
    end)
  end

  defp names(connections) do
    connections
    |> Enum.reject(&(is_nil(&1) or &1.updated_by_platform))
    |> Enum.map(& &1.updated_by_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> %{}
      ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})
    end
  end

  defp with_name(nil, _names), do: nil

  defp with_name(connection, names) do
    Map.put(
      connection,
      :updated_by_name,
      if(connection.updated_by_platform, do: nil, else: names[connection.updated_by_id])
    )
  end

  @doc "A staff member's «Δοκιμή σύνδεσης»."
  def check(context, kind, now \\ DateTime.utc_now()) do
    with {:ok, result} <-
           Connections.check(context, kind, :manual, now, today: local_date(context, now)) do
      {:ok, view(result)}
    end
  end

  @doc false
  # Runs right after a connection is saved; the answer replaces the saved
  # connection so the form shows the check's result under its fields.
  def after_save(context, kind, now \\ DateTime.utc_now()) do
    case Connections.check(context, kind, :saved, now, today: local_date(context, now)) do
      {:ok, result} -> view(result)
      {:error, _reason} -> %{connection: Connections.public(context, kind), check: nil}
    end
  end

  defp view(%{connection: connection} = result) do
    %{
      connection: with_name(connection, names([connection])),
      check: Map.take(result, [:result, :error_code, :detail])
    }
  end

  @doc """
  `:ok`, or `{:error, :fiscal_connections_managed_by_palee}` when the
  Palee team manages the box's connections and `opts[:platform]` is not
  set (only the vendor console sets it).
  """
  def guard(context, opts \\ []) do
    if Keyword.get(opts, :platform) != true and Connections.managed_by(context) == "palee",
      do: {:error, :fiscal_connections_managed_by_palee},
      else: :ok
  end

  # ── Vendor console ──────────────────────────────────────────────────────

  @doc "The box's connections as the Palee team sees them (never a credential)."
  def platform_overview(%PlatformContext{} = platform, organization_id) do
    with {:ok, context} <- tenant(platform, organization_id) do
      {:ok, overview(context)}
    end
  end

  def platform_overview(_context, _organization_id), do: {:error, :vendor_required}

  @doc "The Palee team chooses who manages the box's connections (audited)."
  def set_managed_by(%PlatformContext{} = platform, organization_id, params) do
    managed_by = param(params, :managed_by)

    with :ok <- valid_manager(managed_by),
         {:ok, context} <- tenant(platform, organization_id),
         before = Connections.managed_by(context),
         {:ok, _setting} <- Connections.set_managed_by(context, managed_by, platform.user_id),
         {:ok, _event} <-
           Organizations.record_platform_event(platform, organization_id, %{
             event: "fiscal_connections_manager_changed",
             metadata: %{from: before, to: managed_by}
           }) do
      {:ok, overview(context)}
    end
  end

  def set_managed_by(_context, _organization_id, _params), do: {:error, :vendor_required}

  defp valid_manager(value) do
    if value in ConnectionSetting.managers(),
      do: :ok,
      else: {:error, {:invalid_fields, %{managed_by: ["invalid"]}}}
  end

  @doc """
  The Palee team fills or replaces a box's connection of `kind` with the
  same fields the owner's form sends. Audited without any credential:
  which connection, the environment and whether a secret was replaced.
  """
  def save(platform, organization_id, kind, params, now \\ DateTime.utc_now())

  def save(%PlatformContext{} = platform, organization_id, kind, params, now) do
    with :ok <- known(kind),
         {:ok, context} <- tenant(platform, organization_id),
         {:ok, saved} <- save_kind(context, kind, params, now),
         {:ok, _event} <-
           Organizations.record_platform_event(platform, organization_id, %{
             event: "fiscal_connection_saved",
             metadata: %{
               connection: kind,
               environment: param(params, :environment),
               secrets_replaced: secrets_sent?(params)
             }
           }) do
      {:ok, saved}
    end
  end

  def save(_context, _organization_id, _kind, _params, _now), do: {:error, :vendor_required}

  @doc "The Palee team's «Δοκιμή σύνδεσης» for a box."
  def platform_check(%PlatformContext{} = platform, organization_id, kind) do
    with {:ok, context} <- tenant(platform, organization_id) do
      check(context, kind)
    end
  end

  def platform_check(_context, _organization_id, _kind), do: {:error, :vendor_required}

  defp save_kind(context, "mydata", params, now),
    do: FiscalReporting.save_connection(context, params, now, platform: true)

  defp save_kind(context, "registry", params, now),
    do: FiscalRegistry.save_connection(context, params, now, platform: true)

  defp save_kind(context, "peppol", params, now),
    do: FiscalEInvoicing.save_connection(context, params, now, platform: true)

  defp save_kind(context, device, params, now),
    do: FiscalTillSigning.save_connection(context, device, params, now, platform: true)

  defp known(kind) do
    if kind in Connections.kinds(), do: :ok, else: {:error, :unknown_connection}
  end

  @secrets ~w(subscription_key password api_key api_secret)a

  defp secrets_sent?(params),
    do: Enum.any?(@secrets, &(param(params, &1) not in [nil, ""]))

  # The vendor acts inside the box's tenant (its fiscal tables are
  # tenant-scoped); the acting user stays the vendor, for the journal.
  defp tenant(%PlatformContext{user_id: user_id} = platform, organization_id) do
    if Organizations.platform_organization_exists?(platform, organization_id),
      do: {:ok, %{organization_id: organization_id, user_id: user_id}},
      else: {:error, :not_found}
  end

  # ── Scheduled sweep ─────────────────────────────────────────────────────

  @doc "Checks what is due for one box (scheduled every hour)."
  def check_due(context, now \\ DateTime.utc_now()),
    do: Connections.check_due(context, now, today: local_date(context, now))

  defp local_date(context, now) do
    Organizations.local_date(context, now)
  rescue
    _error -> DateTime.to_date(now)
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp param(_params, _key), do: nil
end
