defmodule Palee.Application.PhoneHealthConnection do
  @moduledoc """
  Apple Health and Health Connect in Εγώ › Συνδεδεμένες συσκευές (ADR-172).
  The store app asks the phone for read access, then:

  - `connect/4`: what to bring in; health data (sleep, weight, resting heart
    rate, steps) needs the health-data consent, which the same request may
    grant (ADR-158 consents). Connecting again only updates the choices.
  - `update/4`: the row's choices, with the same consent rule.
  - `ingest/4`: a batch the app read from the phone, through the same
    import rules as Garmin (dedupe, matching, manual wins, private), so a
    re-read window changes nothing. The row says where to read from next.
  - `disconnect/4`: ends the link; keeps or deletes everything the phone
    brought in, as the person chose (plan D11).

  There are no tokens: the phone holds the permission, the person's session
  carries the batch. Nothing is read on the server's initiative.
  """

  alias Palee.Application.{
    DeviceData,
    DevicePresenter,
    ImportDeviceSummaries,
    WellnessConsent
  }

  alias Palee.Devices

  @doc "The row of `provider` on the devices page."
  def row(%{user_id: user_id} = context, provider) do
    connection =
      Devices.with_context(context, fn -> Devices.get_connection(user_id, provider) end)

    DevicePresenter.phone_row(provider, connection)
  end

  def connect(%{user_id: user_id} = context, provider, params, now \\ DateTime.utc_now()) do
    with :ok <- phone(provider),
         {:ok, prefs} <- Devices.merge_prefs(provider, %{}, param(params, "sync_prefs")),
         :ok <- consent(context, provider, prefs, params, now) do
      Devices.with_context(context, fn ->
        result =
          case Devices.get_connection(user_id, provider) do
            nil ->
              Devices.insert_connection(%{
                user_id: user_id,
                provider: provider,
                status: "active",
                sync_prefs: prefs,
                backfill_days: Devices.phone_history_days(),
                connected_at: now
              })

            %{status: "active"} = connection ->
              Devices.update_connection(connection, %{sync_prefs: prefs})

            connection ->
              Devices.update_connection(connection, %{
                status: "active",
                sync_prefs: prefs,
                connected_at: now,
                last_synced_at: nil,
                revoked_at: nil,
                last_error: nil,
                consecutive_failures: 0
              })
          end

        with {:ok, connection} <- result,
             do: {:ok, DevicePresenter.phone_row(provider, connection)}
      end)
    end
  end

  def update(%{user_id: user_id} = context, provider, params, now \\ DateTime.utc_now()) do
    with :ok <- phone(provider),
         {:ok, connection} <- live(context, user_id, provider),
         {:ok, prefs} <-
           Devices.merge_prefs(provider, connection.sync_prefs, param(params, "sync_prefs")),
         :ok <- consent(context, provider, prefs, params, now) do
      Devices.with_context(context, fn ->
        with {:ok, updated} <- Devices.update_connection(connection, %{sync_prefs: prefs}),
             do: {:ok, DevicePresenter.phone_row(provider, updated)}
      end)
    end
  end

  @doc """
  Imports one batch from the phone. Answers the counts by outcome
  (`imported`, `merged`, `duplicate`, `ignored`, `skipped`, `invalid`, …)
  and the row, whose `read_from` moves on.
  """
  def ingest(%{user_id: user_id} = context, provider, body, now \\ DateTime.utc_now()) do
    with :ok <- phone(provider),
         {:ok, connection} <- live(context, user_id, provider),
         {:ok, batches} <- Devices.phone_health_batches(stringify(body)) do
      counts = ImportDeviceSummaries.import_batches(context, connection, batches, now)

      Devices.with_context(context, fn ->
        with {:ok, synced} <-
               Devices.update_connection(connection, Devices.success_changes(connection, now)) do
          {:ok,
           %{
             counts: Map.new(counts, fn {status, count} -> {to_string(status), count} end),
             row: DevicePresenter.phone_row(provider, synced)
           }}
        end
      end)
    end
  end

  @doc "Ends the link; `delete_data?` also removes everything the phone brought in."
  def disconnect(%{user_id: user_id} = context, provider, delete_data?, now \\ DateTime.utc_now()) do
    with :ok <- phone(provider) do
      Devices.with_context(context, fn ->
        case Devices.get_connection(user_id, provider) do
          nil ->
            {:error, :not_found}

          connection ->
            {:ok, _revoked} =
              Devices.update_connection(connection, %{status: "revoked", revoked_at: now})

            deleted = if delete_data?, do: DeviceData.delete(context, provider), else: nil
            {:ok, %{status: "revoked", deleted: deleted}}
        end
      end)
    end
  end

  defp live(context, user_id, provider) do
    Devices.with_context(context, fn ->
      case Devices.get_connection(user_id, provider) do
        %{status: "active"} = connection -> {:ok, connection}
        _none -> {:error, :phone_health_not_connected}
      end
    end)
  end

  defp phone(provider) do
    if Devices.phone_provider?(provider), do: :ok, else: {:error, :not_found}
  end

  defp consent(context, provider, prefs, params, now) do
    WellnessConsent.for_device(
      context,
      Devices.health_data?(provider, prefs),
      param(params, "health_data_consent"),
      now
    )
  end

  # OpenApiSpex casts known keys to atoms; the domain reads string keys.
  defp stringify(%module{} = value) when module in [Date, DateTime, NaiveDateTime, Time],
    do: value

  defp stringify(%{__struct__: _} = struct), do: struct |> Map.from_struct() |> stringify()

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value

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
