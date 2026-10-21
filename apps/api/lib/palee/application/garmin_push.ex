defmodule Palee.Application.GarminPush do
  @moduledoc """
  Garmin's push endpoint (ADR-161). Garmin POSTs a JSON object keyed by
  summary type; each summary names its Garmin `userId` and either carries
  the data (push mode) or a `callbackURL` to pull it from (ping mode).
  Garmin expects a quick 200 and retries otherwise, so this only verifies
  the request, finds the live connections the user ids belong to, and
  queues one ingest per connection and summary type. Unknown users and
  summary types are ignored; a retried push is harmless because each
  summary is imported once.

  `deregistrations` (the person removed Palee at Garmin) end the link and
  keep the data.
  """

  alias Palee.Application.GarminConnection
  alias Palee.Devices

  @provider "garmin"
  @max_summaries 2_000

  def accept(body, verification) when is_map(body) do
    with :ok <- Devices.garmin().verify_push(verification) do
      deregistrations = list(body, "deregistrations")

      if deregistrations != [],
        do: GarminConnection.deregistered(Enum.map(deregistrations, &Devices.garmin_user_id/1))

      batches =
        for type <- Devices.garmin_summary_types(),
            summaries = list(body, type),
            summaries != [],
            do: {type, Enum.take(summaries, @max_summaries)}

      connections = connections(batches)

      queued =
        for {type, summaries} <- batches,
            {garmin_user_id, own} <- Enum.group_by(summaries, &Devices.garmin_user_id/1),
            connection = Map.get(connections, garmin_user_id),
            connection != nil,
            job <- jobs(connection, type, own) do
          Devices.sync_queue().enqueue_ingest(job)
        end

      ignored =
        Enum.count(
          for({_type, summaries} <- batches, summary <- summaries, do: summary),
          &(not Map.has_key?(connections, Devices.garmin_user_id(&1)))
        )

      {:ok, %{queued: length(queued), deregistered: length(deregistrations), ignored: ignored}}
    end
  end

  def accept(_body, _verification), do: {:error, :invalid_push}

  @doc "Garmin's deregistration endpoint: the same list as in a push."
  def deregister(body, verification) when is_map(body) do
    with :ok <- Devices.garmin().verify_push(verification) do
      ids = body |> list("deregistrations") |> Enum.map(&Devices.garmin_user_id/1)
      GarminConnection.deregistered(Enum.reject(ids, &is_nil/1))
      {:ok, %{deregistered: length(ids)}}
    end
  end

  def deregister(_body, _verification), do: {:error, :invalid_push}

  defp connections(batches) do
    ids =
      for(
        {_type, summaries} <- batches,
        s <- summaries,
        id = Devices.garmin_user_id(s),
        id != nil,
        do: id
      )
      |> Enum.uniq()

    @provider
    |> Devices.connections_for_provider_users(ids)
    |> Enum.filter(&(&1.status in ["active", "error"]))
    |> Map.new(&{&1.provider_user_id, &1})
  end

  # Push mode sends the data; ping mode one callback URL per notification.
  defp jobs(connection, type, summaries) do
    {pings, data} = Enum.split_with(summaries, &is_binary(&1["callbackURL"]))
    base = %{connection_id: connection.id, user_id: connection.user_id, type: type}

    data_jobs = if data == [], do: [], else: [Map.put(base, :summaries, data)]
    ping_jobs = Enum.map(pings, &Map.put(base, :callback_url, &1["callbackURL"]))
    data_jobs ++ ping_jobs
  end

  defp list(body, key) do
    case Map.get(body, key) do
      items when is_list(items) -> Enum.filter(items, &is_map/1)
      _other -> []
    end
  end
end
