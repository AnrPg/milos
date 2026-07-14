defmodule MilosTraining.Infrastructure.Search.MeilisearchMemberIndex do
  @behaviour MilosTraining.Application.Ports.AdminMemberSearchIndex

  require Logger

  @filterable_attributes [
    "identity_role",
    "membership_status",
    "user_type",
    "package_codes",
    "package_families",
    "package_tags"
  ]

  @searchable_attributes ["nickname", "searchable_text"]
  @displayed_attributes ["*"]
  @task_timeout_ms 1_500

  @impl true
  def replace_documents(documents) when is_list(documents) do
    with :ok <- ensure_settings(),
         :ok <- delete_all_documents(),
         :ok <- post_replacement_documents(documents) do
      :ok
    else
      {:error, reason} = error ->
        log_sync_failure(reason)
        error
    end
  end

  @impl true
  def search(params) do
    body = %{
      q: params.query || "",
      limit: params.limit,
      filter: filters(params)
    }

    case request(:post, index_path("/search"), json: body) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        hits = Map.get(body, "hits", [])

        {:ok,
         %{
           users: Enum.map(hits, &normalize_hit/1),
           meta: %{
             search_backend: "meilisearch",
             estimated_total_hits: Map.get(body, "estimatedTotalHits")
           }
         }}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:meilisearch_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_settings do
    body = %{
      searchableAttributes: @searchable_attributes,
      filterableAttributes: @filterable_attributes,
      displayedAttributes: @displayed_attributes
    }

    case request(:patch, index_path("/settings"), json: body) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        body
        |> task_uid()
        |> wait_for_task()

      {:ok, %Req.Response{status: 404}} ->
        create_index()

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:settings_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_index do
    with {:ok, task_uid} <-
           (case request(:post, "/indexes", json: %{uid: index_name(), primaryKey: "id"}) do
              {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
                {:ok, task_uid(body)}

              {:ok, %Req.Response{status: 400, body: %{"code" => "index_already_exists"}}} ->
                {:ok, nil}

              {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {:create_index_status, status, body}}

              {:error, reason} ->
                {:error, reason}
            end),
         :ok <- wait_for_task(task_uid) do
      ensure_settings()
    end
  end

  defp post_documents(documents) do
    case request(:post, index_path("/documents"), json: documents) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, task_uid(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:documents_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_replacement_documents([]), do: :ok

  defp post_replacement_documents(documents) do
    with {:ok, task_uid} <- post_documents(documents),
         :ok <- wait_for_task(task_uid) do
      :ok
    end
  end

  defp delete_all_documents do
    case request(:delete, index_path("/documents")) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        body
        |> task_uid()
        |> wait_for_task()

      {:ok, %Req.Response{status: 404}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:delete_documents_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_task(nil), do: :ok

  defp wait_for_task(task_uid) do
    deadline = System.monotonic_time(:millisecond) + @task_timeout_ms
    poll_task(task_uid, deadline)
  end

  defp poll_task(task_uid, deadline) do
    case request(:get, "/tasks/#{task_uid}") do
      {:ok, %Req.Response{status: status, body: %{"status" => "succeeded"}}}
      when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: %{"status" => "failed"} = body}}
      when status in 200..299 ->
        {:error, {:task_failed, body}}

      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :task_timeout}
        else
          Process.sleep(50)
          poll_task(task_uid, deadline)
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:task_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp filters(params) do
    [
      equality_filter("identity_role", params.role, "all"),
      equality_filter("membership_status", params.membership_status, nil),
      equality_filter("user_type", params.user_type, nil),
      equality_filter("package_codes", params.package_code, nil),
      equality_filter("package_families", params.package_family, nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" AND ")
  end

  defp equality_filter(_field, value, value), do: nil
  defp equality_filter(_field, nil, _empty), do: nil
  defp equality_filter(_field, "", _empty), do: nil
  defp equality_filter(field, value, _empty), do: "#{field} = #{inspect(value)}"

  defp normalize_hit(hit) do
    %{
      id: hit["id"],
      nickname: hit["nickname"],
      identity_role: hit["identity_role"],
      membership: atomize_known_map(hit["membership"]),
      package_subscriptions: Enum.map(hit["package_subscriptions"] || [], &atomize_known_map/1),
      active_package_subscription: atomize_known_map(hit["active_package_subscription"])
    }
  end

  defp atomize_known_map(nil), do: nil

  defp atomize_known_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {String.to_atom(key), value} end)
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
  defp index_name, do: config()[:admin_member_index] || "admin_members"
  defp url(path), do: String.trim_trailing(config()[:url] || "http://localhost:7700", "/") <> path
  defp config, do: Application.get_env(:milos_training, :meilisearch, [])
  defp task_uid(body), do: body["taskUid"] || body["uid"]

  defp log_sync_failure(reason) do
    if Keyword.get(config(), :log_failures, true) do
      Logger.warning("admin_member_search_index sync failed: #{inspect(reason)}")
    else
      Logger.debug("admin_member_search_index sync failed: #{inspect(reason)}")
    end
  end
end
