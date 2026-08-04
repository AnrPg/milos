defmodule MilosTrainingWeb.Plugs.RequireTenantRole do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias MilosTraining.Organizations.Domain.TenantAuthorization

  def init(opts), do: opts

  def call(conn, opts) do
    roles = List.wrap(opts[:role] || opts[:roles])

    case TenantAuthorization.authorize(conn.assigns[:tenant_context], roles) do
      :ok ->
        conn

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{code: "forbidden", error: "Forbidden"})
        |> halt()
    end
  end
end
