defmodule PaleeWeb.BoxScreenTimerChannel do
  @moduledoc """
  `class_timer:<slot_id>` on the box screen's socket (ADR-253): the same
  `class_timer:updated` broadcasts the wall display and phones get
  (`PaleeWeb.ClassTimerChannel`), for a class the screen shows.
  """

  use Phoenix.Channel

  alias Palee.Application.BoxScreens.BoxScreenDisplay

  @impl true
  def join("class_timer:" <> slot_id, _payload, socket) do
    with {:ok, screen} <- BoxScreenDisplay.authenticate(socket.assigns.box_screen_token),
         true <- BoxScreenDisplay.follows_class?(screen, slot_id) do
      {:ok, socket}
    else
      _invalid -> {:error, %{reason: "unauthorized"}}
    end
  end
end
