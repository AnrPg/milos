defmodule MilosTrainingWeb.Plugs.RequireRole do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Guardian.Plug, as: GuardianPlug

  def init(opts), do: opts

  def call(conn, opts) do
    user = GuardianPlug.current_resource(conn)
    allowed_roles = List.wrap(opts[:role] || opts[:roles])

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized"})
        |> halt()

      user.role in allowed_roles ->
        conn

      true ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
        |> halt()
    end
  end
end
