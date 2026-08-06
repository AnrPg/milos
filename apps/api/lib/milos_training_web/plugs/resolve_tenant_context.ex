defmodule MilosTrainingWeb.Plugs.ResolveTenantContext do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.ResolveTenantContext

  def init(opts), do: opts

  def call(conn, _opts) do
    account = GuardianPlug.current_resource(conn)

    case conn.path_params["organization_slug"] do
      slug when is_binary(slug) and slug != "" ->
        case ResolveTenantContext.call(account, slug, request_metadata(conn)) do
          {:ok, context} ->
            conn
            |> assign(:tenant_context, context)
            |> drop_organization_slug_path_param()

          {:error, _reason} ->
            conn
            |> put_status(:not_found)
            |> json(%{code: "organization_context_not_found", error: "Organization not found"})
            |> halt()
        end

      _missing ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          code: "organization_context_required",
          error: "Organization must be identified in the request path"
        })
        |> halt()
    end
  end

  defp drop_organization_slug_path_param(conn) do
    %{
      conn
      | path_params: Map.delete(conn.path_params, "organization_slug"),
        params: Map.delete(conn.params, "organization_slug")
    }
  end

  defp request_metadata(conn) do
    %{
      transport: :http,
      method: conn.method,
      request_id: List.first(get_resp_header(conn, "x-request-id"))
    }
  end
end
