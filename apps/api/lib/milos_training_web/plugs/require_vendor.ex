defmodule MilosTrainingWeb.Plugs.RequireVendor do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.ResolvePlatformContext

  def init(opts), do: opts

  def call(conn, _opts) do
    case ResolvePlatformContext.call(GuardianPlug.current_resource(conn), request_metadata(conn)) do
      {:ok, context} ->
        assign(conn, :platform_context, context)

      {:error, _reason} ->
        conn
        |> put_status(:forbidden)
        |> json(%{code: "vendor_required", error: "Forbidden"})
        |> halt()
    end
  end

  defp request_metadata(conn) do
    %{
      transport: :http,
      method: conn.method,
      request_id: List.first(get_resp_header(conn, "x-request-id"))
    }
  end
end
