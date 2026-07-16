defmodule MilosTraining.Messaging.Application.ListMessages do
  alias MilosTraining.Messaging.Domain.ThreadPolicy
  alias MilosTraining.Messaging.{MessageStore, ThreadStore}

  @default_limit 50
  @maximum_limit 100

  def call(thread_id, params \\ %{}) do
    case ThreadStore.get_thread_with_participants(thread_id) do
      nil ->
        {:error, :not_found}

      thread ->
        actor_id = Map.get(params, :actor_id)

        with :ok <- authorize(actor_id, thread),
             {:ok, pagination} <- normalize_pagination(thread_id, params) do
          {:ok, MessageStore.list_messages(thread_id, pagination)}
        end
    end
  end

  defp authorize(nil, _thread), do: :ok
  defp authorize(actor_id, thread), do: ThreadPolicy.can_read?(actor_id, thread)

  defp normalize_pagination(thread_id, params) do
    with {:ok, limit} <- normalize_limit(Map.get(params, :limit)),
         {:ok, before_id} <- normalize_before_id(thread_id, Map.get(params, :before_id)) do
      {:ok, %{limit: limit, before_id: before_id}}
    end
  end

  defp normalize_limit(nil), do: {:ok, @default_limit}

  defp normalize_limit(value) when is_integer(value) and value in 1..@maximum_limit,
    do: {:ok, value}

  defp normalize_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> normalize_limit(integer)
      _other -> {:error, :bad_request}
    end
  end

  defp normalize_limit(_value), do: {:error, :bad_request}

  defp normalize_before_id(_thread_id, nil), do: {:ok, nil}

  defp normalize_before_id(thread_id, before_id) when is_binary(before_id) do
    case Ecto.UUID.cast(before_id) do
      {:ok, uuid} ->
        case MessageStore.get_message(uuid) do
          %{thread_id: ^thread_id} -> {:ok, uuid}
          _other -> {:error, :bad_request}
        end

      :error ->
        {:error, :bad_request}
    end
  end

  defp normalize_before_id(_thread_id, _before_id), do: {:error, :bad_request}
end
