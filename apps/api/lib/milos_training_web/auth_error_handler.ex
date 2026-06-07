defmodule MilosTrainingWeb.AuthErrorHandler do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def auth_error(conn, {_type, _reason}, _opts) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Unauthorized"})
  end
end
