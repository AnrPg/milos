defmodule MilosTrainingWeb.ChatChannel do
  use Phoenix.Channel

  alias MilosTraining.Messaging
  alias MilosTraining.Application.SendMessage

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
    client_operation_id = Map.get(params, "client_operation_id")

    case SendMessage.call(socket.assigns.current_user, %{
           thread_id: thread_id,
           sender_id: user_id,
           body: body,
           message_type: message_type,
           client_operation_id: client_operation_id
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
  def handle_in("typing_start", _payload, socket), do: broadcast_typing(socket, true)

  @impl true
  def handle_in("typing_stop", _payload, socket), do: broadcast_typing(socket, false)

  @impl true
  def handle_in("mark_read", %{"message_id" => message_id}, socket) do
    user_id = socket.assigns.current_user.id
    thread_id = socket.assigns.thread_id

    case Messaging.mark_read(thread_id, user_id, message_id) do
      {:ok, result} -> {:reply, {:ok, result}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, %{reason: "unsupported_event"}}, socket}

  defp broadcast_typing(socket, typing) do
    user_id = socket.assigns.current_user.id
    nickname = socket.assigns.current_user.nickname

    broadcast_from!(socket, "typing", %{
      user_id: user_id,
      nickname: nickname,
      typing: typing
    })

    {:reply, {:ok, %{typing: typing}}, socket}
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      thread_id: message.thread_id,
      sender_id: message.sender_id,
      body: message.body,
      message_type: message.message_type,
      client_operation_id: message.client_operation_id,
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
