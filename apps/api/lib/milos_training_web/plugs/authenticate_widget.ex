defmodule MilosTrainingWeb.Plugs.AuthenticateWidget do
  @moduledoc """
  Home-screen widgets (ADR-173) send `Authorization: Bearer <widget token>`;
  this assigns the person's `user_context` or answers 401
  `invalid_widget_token`. The token is not a session: it opens nothing but
  the widget endpoints.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias MilosTraining.Application.WidgetAccess

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, context} <- WidgetAccess.authenticate(String.trim(token)) do
      assign(conn, :user_context, context)
    else
      _missing_or_invalid ->
        conn
        |> put_status(:unauthorized)
        |> json(%{code: "invalid_widget_token", error: "Open the app to refresh the widget"})
        |> halt()
    end
  end
end
