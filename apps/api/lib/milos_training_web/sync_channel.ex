defmodule MilosTrainingWeb.SyncChannel do
  use Phoenix.Channel

  @impl true
  def join("sync:" <> user_id, _payload, socket) do
    current_user = socket.assigns.current_user

    if current_user.id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end
end
