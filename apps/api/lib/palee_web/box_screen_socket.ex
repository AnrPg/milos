defmodule PaleeWeb.BoxScreenSocket do
  @moduledoc """
  The box screen's socket (`/box_screen_socket`, ADR-253). It accepts only
  a display token (`params.token`), never a person's session, and opens two
  kinds of topic:

    * `box_screen:<organization_id>` – refresh hints and the screen's own
      override;
    * `class_timer:<slot_id>` – the class timer, for classes the screen
      shows.

  Removing the screen or pairing another device closes it
  (`socket_id/1`).
  """

  use Phoenix.Socket

  alias Palee.Application.BoxScreens.BoxScreenDisplay

  channel "box_screen:*", PaleeWeb.BoxScreenChannel
  channel "class_timer:*", PaleeWeb.BoxScreenTimerChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case BoxScreenDisplay.authenticate(token) do
      {:ok, %{screen: screen}} ->
        {:ok,
         socket
         |> assign(:box_screen_token, token)
         |> assign(:box_screen_id, screen.id)
         |> assign(:organization_id, screen.organization_id)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: socket_id(socket.assigns.box_screen_id)

  def socket_id(screen_id), do: "box_screen_socket:#{screen_id}"
end
