defmodule PaleeWeb.BoxScreenChannel do
  @moduledoc """
  `box_screen:<organization_id>` (ADR-253): every screen of a box hears
  `box_screen:refresh` `%{kind, slot_id}` (read `/today` again; never who),
  and each screen alone hears `box_screen:override` `%{override}` when staff
  pin what it shows or return it to automatic.
  """

  use Phoenix.Channel

  alias Palee.Application.BoxScreens.BoxScreenDisplay

  intercept ["box_screen:override"]

  @impl true
  def join("box_screen:" <> organization_id, _payload, socket) do
    with {:ok, %{screen: screen}} <- BoxScreenDisplay.authenticate(socket.assigns.box_screen_token),
         ^organization_id <- screen.organization_id do
      {:ok, socket}
    else
      _invalid -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_out("box_screen:override", %{screen_id: screen_id, override: override}, socket) do
    if screen_id == socket.assigns.box_screen_id,
      do: push(socket, "box_screen:override", %{override: override})

    {:noreply, socket}
  end
end
