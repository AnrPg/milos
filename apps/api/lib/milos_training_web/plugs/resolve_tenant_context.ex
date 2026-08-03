defmodule MilosTrainingWeb.Plugs.ResolveTenantContext do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.ResolveTenantContext

  def init(opts), do: opts

  def call(conn, _opts) do
    account = GuardianPlug.current_resource(conn)
    slug =
      conn.path_params["organization_slug"] ||
        List.first(get_req_header(conn, "x-organization-slug")) ||
        MilosTraining.Organizations.legacy_organization_slug()

    case ResolveTenantContext.call(account, slug, request_metadata(conn)) do
      {:ok, context} ->
        assign(conn, :tenant_context, context)

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{code: "organization_context_not_found", error: "Organization not found"})
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
