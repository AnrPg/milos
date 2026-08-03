defmodule MilosTrainingWeb.Plugs.AssignUserContext do
  import Plug.Conn

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Identity.UserContext

  def init(opts), do: opts

  def call(conn, _opts) do
    case GuardianPlug.current_resource(conn) do
      nil -> conn
      account -> assign(conn, :user_context, UserContext.new(account, request_metadata(conn)))
    end
  end

  defp request_metadata(conn) do
    %{transport: :http, request_id: List.first(get_resp_header(conn, "x-request-id"))}
  end
end
