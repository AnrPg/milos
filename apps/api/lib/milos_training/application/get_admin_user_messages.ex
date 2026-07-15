defmodule MilosTraining.Application.GetAdminUserMessages do
  @moduledoc false

  alias MilosTraining.{Identity, Messaging}

  def call(user_id) do
    with %{} <- Identity.find_by_id(user_id) || {:error, :not_found} do
      threads =
        Messaging.list_threads_for_user(user_id) |> Enum.map(&serialize_thread(&1, user_id))

      {:ok,
       %{
         user_id: user_id,
         threads: threads,
         summary: %{
           thread_count: length(threads),
           unread_thread_count: Messaging.count_unread_threads(user_id)
         },
         operational_links: %{workspace: "/account/activity/chats"}
       }}
    end
  end

  defp serialize_thread(thread, user_id) do
    messages =
      case Messaging.list_messages(thread.id, %{limit: 100, actor_id: user_id}) do
        {:ok, messages} -> messages
        _ -> []
      end

    %{
      id: thread.id,
      context_type: to_string(thread.context_type),
      context_id: thread.context_id,
      created_by_id: thread.created_by_id,
      participant_ids: Enum.map(thread.participants || [], & &1.user_id),
      message_count: length(messages),
      latest_message: messages |> List.last() |> serialize_message()
    }
  end

  defp serialize_message(nil), do: nil

  defp serialize_message(message),
    do: Map.take(message, [:id, :thread_id, :sender_id, :body, :message_type, :inserted_at])
end
