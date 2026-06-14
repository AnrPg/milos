defmodule MilosTrainingWeb.UserSocket do
  use Phoenix.Socket

  alias MilosTraining.Infrastructure.Auth.Guardian

  channel "schedule:lobby", MilosTrainingWeb.ScheduleChannel
  channel "notifications:*", MilosTrainingWeb.NotificationChannel
  channel "sync:*", MilosTrainingWeb.SyncChannel
  channel "execution:*", MilosTrainingWeb.ExecutionChannel
  channel "chat:*", MilosTrainingWeb.ChatChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    with {:ok, claims} <- Guardian.decode_and_verify(token, %{"typ" => "access"}),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      {:ok, assign(socket, :current_user, user)}
    else
      _error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
