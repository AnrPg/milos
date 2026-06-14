defmodule MilosTrainingWeb.ChatChannel do
  use Phoenix.Channel

  alias MilosTraining.Messaging

  @impl true
  def join("chat:thread:" <> thread_id, _payload, socket) do
    user_id = socket.assigns.current_user.id

    case Messaging.get_thread(thread_id, user_id) do
      {:ok, thread} ->
        {:ok, %{thread_id: thread.id}, assign(socket, :thread_id, thread.id)}

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}

      {:error, :forbidden} ->
        {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_in("send_message", %{"body" => body} = params, socket) do
    user_id = socket.assigns.current_user.id
    thread_id = socket.assigns.thread_id
    message_type = parse_message_type(Map.get(params, "message_type", "chat"))

    case Messaging.send_message(%{
           thread_id: thread_id,
           sender_id: user_id,
           body: body,
           message_type: message_type
         }) do
      {:ok, message} ->
        {:reply, {:ok, serialize_message(message)}, socket}

      {:error, :forbidden} ->
        {:reply, {:error, %{reason: "forbidden"}}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{reason: format_errors(changeset)}}, socket}
    end
  end

  @impl true
  def handle_in("typing", _payload, socket) do
    user_id = socket.assigns.current_user.id
    thread_id = socket.assigns.thread_id

    broadcast_from!(socket, "typing", %{user_id: user_id, thread_id: thread_id})
    {:noreply, socket}
  end

  @impl true
  def handle_in("mark_read", %{"message_id" => message_id}, socket) do
    user_id = socket.assigns.current_user.id
    thread_id = socket.assigns.thread_id

    Messaging.mark_read(thread_id, user_id, message_id)
    {:noreply, socket}
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      thread_id: message.thread_id,
      sender_id: message.sender_id,
      body: message.body,
      message_type: message.message_type,
      inserted_at: message.inserted_at
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp format_errors(reason), do: inspect(reason)

  defp parse_message_type("coaching_note"), do: :coaching_note
  defp parse_message_type("system"), do: :system
  defp parse_message_type(_), do: :chat
end
