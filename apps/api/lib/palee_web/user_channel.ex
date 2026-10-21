defmodule PaleeWeb.UserChannel do
  @moduledoc """
  A person's own account-scoped live updates (`user:<user_id>`), for data
  that belongs to the account rather than a gym, such as Buddy για στήριξη
  (ADR-160). Only the socket's own user can join: the token's subject must
  be the topic's id; no gym context is needed or consulted.
  """

  use Phoenix.Channel

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if socket.assigns.current_user.id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end
end
