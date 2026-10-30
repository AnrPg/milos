defmodule PaleeWeb.Plugs.AuthenticateBoxScreen do
  @moduledoc """
  Box screens (ADR-253) send `Authorization: Bearer <display token>`; this
  assigns `box_screen` (`%{context, screen}`) and the rate limiter's actor,
  or answers 401 `invalid_screen_token`. The token opens nothing but
  `/api/box-screen/*`.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Palee.Application.BoxScreens.BoxScreenDisplay

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, box_screen} <- BoxScreenDisplay.authenticate(String.trim(token)) do
      conn
      |> assign(:box_screen, box_screen)
      |> assign(:rate_limit_actor, "box-screen:" <> box_screen.screen.id)
    else
      _missing_or_invalid ->
        conn
        |> put_status(:unauthorized)
        |> json(%{code: "invalid_screen_token", error: "Pair this screen again"})
        |> halt()
    end
  end
end
