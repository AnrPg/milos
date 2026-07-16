defmodule MilosTrainingWeb.Plugs.LoggerUserMetadata do
  def init(options), do: options

  def call(conn, _options) do
    case Guardian.Plug.current_resource(conn) do
      %{id: user_id, role: role} -> Logger.metadata(user_id: user_id, user_role: role)
      _other -> :ok
    end

    conn
  end
end
