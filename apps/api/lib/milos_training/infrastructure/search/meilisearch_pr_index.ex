defmodule MilosTraining.Infrastructure.Search.MeilisearchPRIndex do
  @behaviour MilosTraining.Application.Ports.PRSearchIndex

  require Logger

  alias MilosTraining.Workers.SyncPRSearchJob
  alias MilosTraining.Repo

  @filterable_attributes ["user_id"]
  @searchable_attributes ["name"]

  @impl true
  def enqueue_upsert(pr) do
    pr
    |> serialize()
    |> then(&SyncPRSearchJob.new(%{"operation" => "upsert", "pr" => &1}))
    |> Repo.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def enqueue_delete(id) do
    %{"operation" => "delete", "id" => id}
    |> SyncPRSearchJob.new()
    |> Repo.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def upsert_document(pr) do
    with :ok <- ensure_settings() do
      case request(:post, index_path("/documents"), json: [serialize(pr)]) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          :ok

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:meilisearch_status, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def delete_document(pr_id) do
    case request(:delete, index_path("/documents/#{pr_id}")) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:meilisearch_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def search(user_id, query) do
    body = %{
      q: query,
      filter: "user_id = \"#{user_id}\"",
      limit: 100
    }

    case request(:post, index_path("/search"), json: body) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, Enum.map(Map.get(body, "hits", []), & &1["id"])}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:meilisearch_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_settings do
    body = %{
      filterableAttributes: @filterable_attributes,
      searchableAttributes: @searchable_attributes
    }

    case request(:patch, index_path("/settings"), json: body) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      _ -> :ok
    end
  end

  defp serialize(pr) do
    %{
      id: pr[:id] || pr["id"],
      user_id: pr[:user_id] || pr["user_id"],
      name: pr[:name] || pr["name"]
    }
  end

  defp request(method, path, opts \\ []) do
    Req.request(
      Keyword.merge(
        [
          method: method,
          url: url(path),
          headers: headers(),
          receive_timeout: 1_500,
          retry: false
        ],
        opts
      )
    )
  end

  defp headers do
    case config()[:api_key] do
      nil -> []
      "" -> []
      api_key -> [{"authorization", "Bearer #{api_key}"}]
    end
  end

  defp index_path(suffix), do: "/indexes/#{index_name()}#{suffix}"
  defp index_name, do: "user_pr_records"
  defp url(path), do: String.trim_trailing(config()[:url] || "http://localhost:7700", "/") <> path
  defp config, do: Application.get_env(:milos_training, :meilisearch, [])
end
