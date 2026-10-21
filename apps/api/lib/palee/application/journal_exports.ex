defmodule Palee.Application.JournalExports do
  @moduledoc """
  «Εξαγωγή» of the whole journal across providers (ADR-162, board 17
  extra), from Ρυθμίσεις: `POST /api/me/journal/export` records a request
  and a background job (`JournalExportJob`) builds `journal.json` (every
  entry with its source) and `training.csv`, stores them privately under
  the member's own prefix and notifies them. `GET /api/me/journal/exports`
  lists the exports with short-lived download links while they are kept
  (seven days). One export may be pending at a time.
  """

  require Logger

  alias Palee.Application.{JournalAudience, JournalFeed, MediaStorage}
  alias Palee.Journal.Domain.ExportFormat
  alias Palee.{Journal, Notifications, Organizations}
  alias Palee.Workers.JournalExportJob

  @bucket :media_private
  @keep_days 7
  @page 100
  @max_pages 500

  def request(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    Journal.with_context(context, fn ->
      if Enum.any?(Journal.list_exports(user_id), &(&1.status == "pending")),
        do: {:error, :export_in_progress},
        else: Journal.insert_export(%{user_id: user_id, requested_at: now})
    end)
    |> case do
      {:ok, export} ->
        :ok = enqueue(user_id, export.id)
        {:ok, view(context, reload(context, export.id), now)}

      error ->
        error
    end
  end

  def list(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    exports = Journal.with_context(context, fn -> Journal.list_exports(user_id) end)
    {:ok, Enum.map(exports, &view(context, &1, now))}
  end

  @doc "Builds one export (the job's work), in the member's session."
  def build(%{user_id: user_id} = context, export_id, now \\ DateTime.utc_now()) do
    case Journal.with_context(context, fn -> Journal.get_export(export_id, user_id) end) do
      %{status: "pending"} = export -> run(context, export, now)
      nil -> {:ok, :gone}
      _done -> {:ok, :skipped}
    end
  end

  defp run(%{user_id: user_id} = context, export, now) do
    providers = Organizations.list_my_providers(context)
    member = JournalAudience.member(context, providers)
    owner = MediaStorage.owner(context, :account)

    items =
      Journal.with_context(context, fn ->
        context |> all_items(nil, [], 0) |> JournalAudience.annotate(context, providers, member)
      end)

    files = [
      {"journal.json", "application/json", ExportFormat.json(items, providers, now)},
      {"training.csv", "text/csv", ExportFormat.training_csv(items)}
    ]

    with {:ok, stored} <- store(owner, export.id, files) do
      {:ok, finished} =
        finish(context, export, %{
          status: "ready",
          entry_count: length(items),
          files: stored,
          completed_at: now,
          expires_at: DateTime.add(now, @keep_days * 86_400, :second)
        })

      Notifications.dispatch_event(:journal_export_ready, %{
        user_id: user_id,
        export_id: export.id,
        dedupe_key: "journal_export:#{export.id}"
      })

      {:ok, finished}
    end
  end

  @doc "Marks an export failed for good (the job's last attempt)."
  def fail(%{user_id: user_id} = context, export_id, reason) do
    case Journal.with_context(context, fn -> Journal.get_export(export_id, user_id) end) do
      %{status: "pending"} = export ->
        finish(context, export, %{status: "failed", error: inspect(reason)})

      _other ->
        {:ok, :skipped}
    end
  end

  defp all_items(_context, _cursor, acc, @max_pages), do: acc

  defp all_items(%{user_id: user_id} = context, cursor, acc, pages) do
    {:ok, page} = JournalFeed.page(user_id, :owner, %{"limit" => @page, "cursor" => cursor})
    acc = acc ++ page.items

    if page.next_cursor,
      do: all_items(context, page.next_cursor, acc, pages + 1),
      else: acc
  end

  defp store(owner, export_id, files) do
    Enum.reduce_while(files, {:ok, []}, fn {name, type, body}, {:ok, acc} ->
      key = MediaStorage.object_key(owner, "exports/journal/#{export_id}/#{name}")

      case MediaStorage.put(owner, @bucket, key, body, type) do
        {:ok, _stored} ->
          {:cont,
           {:ok, acc ++ [%{name: name, key: key, content_type: type, bytes: byte_size(body)}]}}

        :ok ->
          {:cont,
           {:ok, acc ++ [%{name: name, key: key, content_type: type, bytes: byte_size(body)}]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp finish(context, export, attrs),
    do: Journal.with_context(context, fn -> Journal.finish_export(export, attrs) end)

  defp reload(%{user_id: user_id} = context, id),
    do: Journal.with_context(context, fn -> Journal.get_export(id, user_id) end)

  defp view(context, export, now) do
    live? = export.status == "ready" and DateTime.compare(export.expires_at, now) == :gt

    %{
      id: export.id,
      status: if(export.status == "ready" and not live?, do: "expired", else: export.status),
      entry_count: export.entry_count,
      requested_at: export.requested_at,
      completed_at: export.completed_at,
      expires_at: export.expires_at,
      files: if(live?, do: Enum.map(export.files, &file(context, &1)), else: [])
    }
  end

  defp file(context, file) do
    owner = MediaStorage.owner(context, :account)
    key = file["key"] || file[:key]

    url =
      case MediaStorage.read_url(owner, @bucket, key) do
        {:ok, url} -> url
        _error -> nil
      end

    %{
      name: file["name"] || file[:name],
      content_type: file["content_type"] || file[:content_type],
      bytes: file["bytes"] || file[:bytes],
      download_url: url
    }
  end

  defp enqueue(user_id, export_id) do
    if Application.get_env(:palee, :start_oban, true) do
      {:ok, _job} =
        %{"user_id" => user_id, "export_id" => export_id}
        |> JournalExportJob.new()
        |> Oban.insert()

      :ok
    else
      _result = build(%{user_id: user_id}, export_id)
      :ok
    end
  rescue
    error ->
      Logger.error("journal export enqueue failed export_id=#{export_id} error=#{inspect(error)}")
      :ok
  end
end
