defmodule PaleeWeb.CommunityChannel do
  @moduledoc """
  `community:club:<club_id>` (ADR-138): tells the members of a club that a
  post was created, changed or removed, so open feeds refetch. Joined only
  by members of the gym that runs the club.
  """

  use Phoenix.Channel

  alias Palee.Application.ClubScope

  @impl true
  def join("community:club:" <> club_id, _payload, socket) do
    with {:ok, clubs} <- ClubScope.call(socket.assigns.user_context),
         true <- Enum.any?(clubs, &(&1.id == club_id)) do
      {:ok, socket}
    else
      _reason -> {:error, %{reason: "unauthorized"}}
    end
  end
end
