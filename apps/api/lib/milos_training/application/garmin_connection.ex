defmodule MilosTraining.Application.GarminConnection do
  @moduledoc """
  Garmin in Εγώ › Συνδεδεμένες συσκευές (ADR-161, board 16 Q1, Q5, Q6):

  - `connect/3`: what to bring in and how far back, then Garmin's sign-in
    (OAuth 2 with PKCE; the verifier stays on the server, encrypted). Needs
    the health-data consent, which the request may grant in the same step.
  - `complete/2`: Garmin's return. The `state` names the sign-in; the code
    is exchanged, the Garmin user id fetched, and the history import queued.
  - `update/2`, `sync_now/2`: the row's choices and «Συγχρονισμός τώρα»
    (at most every five minutes; it asks Garmin to resend the last two days).
  - `disconnect/3`: ends the link at Garmin, then here; keeps or deletes
    everything that came from Garmin, as the person chose.
  - `deregistered/1`: the person removed Milos at Garmin's side.

  Without `GARMIN_CLIENT_ID`/`GARMIN_CLIENT_SECRET` the row says «Σύντομα»
  (`unavailable`) and `connect/3` answers `garmin_not_configured`.
  """

  require Logger

  alias MilosTraining.Application.{DeviceData, DevicePresenter, DeviceTokens, WellnessConsent}
  alias MilosTraining.{Body, Devices}

  @provider "garmin"
  @recent_seconds 2 * 86_400

  def provider, do: @provider

  @doc "The Garmin row of the devices page."
  def row(%{user_id: user_id} = context) do
    connection =
      Devices.with_context(context, fn -> Devices.get_connection(user_id, @provider) end)

    DevicePresenter.garmin_row(connection, Devices.garmin().configured?())
  end

  def connect(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with :ok <- configured(),
         :ok <- consent(context, params, now),
         {:ok, days} <- Devices.validate_backfill_days(param(params, "backfill_days")),
         {:ok, prefs} <- Devices.merge_prefs(%{}, param(params, "sync_prefs")) do
      verifier = Devices.pkce_verifier(:crypto.strong_rand_bytes(48))
      state = Devices.oauth_state(:crypto.strong_rand_bytes(32))

      attrs = %{
        status: "pending",
        sync_prefs: prefs,
        backfill_days: days,
        oauth_state_hash: Devices.oauth_state_hash(state),
        pkce_verifier: verifier,
        oauth_started_at: now
      }

      with {:ok, _connection} <- save_pending(context, user_id, attrs),
           {:ok, url} <-
             Devices.garmin().authorize_url(%{
               state: state,
               challenge: Devices.pkce_challenge(verifier)
             }) do
        {:ok,
         %{
           authorize_url: url,
           expires_at: DateTime.add(now, 15 * 60, :second)
         }}
      end
    end
  end

  defp save_pending(context, user_id, attrs) do
    Devices.with_context(context, fn ->
      case Devices.get_connection(user_id, @provider) do
        nil ->
          Devices.insert_connection(Map.merge(attrs, %{user_id: user_id, provider: @provider}))

        %{status: "active"} ->
          {:error, :device_already_connected}

        connection ->
          Devices.update_connection(connection, attrs)
      end
    end)
  end

  @doc """
  Garmin's return (`code` and `state`, or `error`). Answers `{:ok, :connected}`
  or `{:error, reason}`; the controller turns either into a redirect.
  """
  def complete(params, now \\ DateTime.utc_now()) do
    state = param(params, "state")

    with true <- is_binary(state) || {:error, :invalid_oauth_state},
         {:ok, user_id} <- sign_in_owner(state) do
      context = %{user_id: user_id}

      Devices.with_context(context, fn ->
        connection = Devices.get_connection(user_id, @provider)

        cond do
          is_nil(connection) or connection.status != "pending" ->
            {:error, :invalid_oauth_state}

          Devices.sign_in_expired?(connection.oauth_started_at, now) ->
            clear_sign_in(connection)
            {:error, :oauth_sign_in_expired}

          is_binary(param(params, "error")) or not is_binary(param(params, "code")) ->
            clear_sign_in(connection)
            {:error, :garmin_access_denied}

          true ->
            finish(context, connection, param(params, "code"), now)
        end
      end)
    end
  end

  defp sign_in_owner(state) do
    case Devices.connection_by_oauth_state(Devices.oauth_state_hash(state)) do
      {_id, user_id} -> {:ok, user_id}
      nil -> {:error, :invalid_oauth_state}
    end
  end

  defp finish(context, connection, code, now) do
    with {:ok, tokens} <-
           Devices.garmin().exchange_code(%{code: code, verifier: connection.pkce_verifier}),
         {:ok, garmin_user_id} <- Devices.garmin().user_id(tokens.access_token) do
      scopes =
        case Devices.garmin().permissions(tokens.access_token) do
          {:ok, permissions} when permissions != [] -> permissions
          _none -> tokens.scopes
        end

      windows = Devices.backfill_windows(connection.backfill_days, now)

      attrs =
        tokens
        |> DeviceTokens.token_attrs(now)
        |> Map.merge(%{
          status: "active",
          provider_user_id: garmin_user_id,
          scopes: scopes,
          oauth_state_hash: nil,
          pkce_verifier: nil,
          oauth_started_at: nil,
          connected_at: now,
          revoked_at: nil,
          consecutive_failures: 0,
          last_error: nil,
          error_notified_at: nil,
          backfill_status: if(windows == [], do: "none", else: "running"),
          backfill_windows_total: length(windows),
          backfill_windows_done: 0
        })

      case Devices.update_connection(connection, attrs) do
        {:ok, connected} ->
          if windows != [],
            do: Devices.sync_queue().enqueue_backfill(connected.id, context.user_id)

          {:ok, :connected}

        {:error, %Ecto.Changeset{errors: errors}} ->
          if Keyword.has_key?(errors, :provider),
            do: {:error, :garmin_account_in_use},
            else: {:error, :garmin_connect_failed}
      end
    else
      {:error, reason} ->
        Logger.warning("garmin connect failed #{inspect(reason)}")
        clear_sign_in(connection)
        {:error, :garmin_connect_failed}
    end
  end

  defp clear_sign_in(connection) do
    Devices.update_connection(connection, %{
      oauth_state_hash: nil,
      pkce_verifier: nil,
      oauth_started_at: nil,
      status: if(connection.access_token, do: connection.status, else: "revoked")
    })
  end

  @doc "Changes what syncs (`sync_prefs`)."
  def update(%{user_id: user_id} = context, params) do
    Devices.with_context(context, fn ->
      with {:ok, connection} <- live(user_id),
           {:ok, prefs} <-
             Devices.merge_prefs(connection.sync_prefs, param(params, "sync_prefs")),
           {:ok, updated} <- Devices.update_connection(connection, %{sync_prefs: prefs}) do
        {:ok, DevicePresenter.garmin_row(updated, true)}
      end
    end)
  end

  @doc "«Συγχρονισμός τώρα»: Garmin resends the last two days to the push endpoint."
  def sync_now(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    Devices.with_context(context, fn ->
      with {:ok, connection} <- live(user_id),
           :ok <- Devices.validate_sync_request(connection.last_sync_requested_at, now),
           {:ok, connection} <-
             Devices.update_connection(connection, %{last_sync_requested_at: now}),
           {:ok, token, connection} <- DeviceTokens.access_token(context, connection, now) do
        from = DateTime.add(now, -@recent_seconds, :second)

        connection.sync_prefs
        |> wanted_kinds()
        |> Devices.garmin_backfill_types()
        |> Enum.reduce_while(:ok, fn type, :ok ->
          case Devices.garmin().request_backfill(token, type, from, now) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          :ok ->
            {:ok, DevicePresenter.garmin_row(connection, true)}

          {:error, reason} ->
            DeviceTokens.record_failure(context, connection, inspect(reason))
            {:error, :garmin_unavailable}
        end
      end
    end)
  end

  @doc "Ends the link; `delete_data?` also removes everything Garmin brought in."
  def disconnect(%{user_id: user_id} = context, delete_data?, now \\ DateTime.utc_now()) do
    Devices.with_context(context, fn ->
      case Devices.get_connection(user_id, @provider) do
        nil ->
          {:error, :not_found}

        connection ->
          deregister_at_garmin(context, connection, now)

          {:ok, _revoked} =
            Devices.update_connection(connection, revoked_attrs(now))

          deleted = if delete_data?, do: DeviceData.delete(context, @provider), else: nil
          {:ok, %{status: "revoked", deleted: deleted}}
      end
    end)
  end

  defp deregister_at_garmin(context, %{access_token: access} = connection, now)
       when is_binary(access) do
    with {:ok, token, _connection} <- DeviceTokens.access_token(context, connection, now),
         :ok <- Devices.garmin().deregister(token) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("garmin deregistration failed #{inspect(reason)}; revoking locally")
        :ok
    end
  end

  defp deregister_at_garmin(_context, _connection, _now), do: :ok

  @doc "Garmin says these users removed Milos: the links end, the data stays."
  def deregistered(garmin_user_ids, now \\ DateTime.utc_now()) do
    @provider
    |> Devices.connections_for_provider_users(Enum.uniq(garmin_user_ids))
    |> Enum.each(fn %{user_id: user_id} ->
      Devices.with_context(%{user_id: user_id}, fn ->
        case Devices.get_connection(user_id, @provider) do
          nil -> :ok
          connection -> Devices.update_connection(connection, revoked_attrs(now))
        end
      end)
    end)
  end

  defp revoked_attrs(now) do
    %{
      status: "revoked",
      access_token: nil,
      refresh_token: nil,
      token_expires_at: nil,
      refresh_token_expires_at: nil,
      oauth_state_hash: nil,
      pkce_verifier: nil,
      backfill_status: "none",
      backfill_windows_total: 0,
      backfill_windows_done: 0,
      revoked_at: now
    }
  end

  defp live(user_id) do
    case Devices.get_connection(user_id, @provider) do
      %{status: status} = connection when status in ["active", "error"] -> {:ok, connection}
      _none -> {:error, :device_not_connected}
    end
  end

  defp wanted_kinds(prefs),
    do: Enum.filter(~w(activity sleep weight daily), &Devices.wanted?(prefs, &1))

  defp configured do
    if Devices.garmin().configured?(), do: :ok, else: {:error, :garmin_not_configured}
  end

  # Board 16 brings sleep, weight and heart rate in: health data (plan D8).
  defp consent(%{user_id: user_id} = context, params, now) do
    cond do
      WellnessConsent.active?(context, user_id) ->
        :ok

      param(params, "health_data_consent") in [true, "true"] ->
        with {:ok, _consent} <-
               Body.grant_consent(context, user_id, WellnessConsent.scope(), now),
             do: :ok

      true ->
        {:error, :health_data_consent_required}
    end
  end

  # Request bodies arrive with string keys, or atom keys once cast by OpenApiSpex.
  defp param(params, key) when is_map(params) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(params, fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
    end
  end

  defp param(_params, _key), do: nil
end
