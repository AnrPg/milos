defmodule MilosTrainingWeb.AuthErrorHandler do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  # Guardian's documented failure types. Anything else is collapsed so the
  # telemetry label set stays bounded.
  @known_types ~w(invalid_token unauthenticated already_authenticated no_resource_found)a

  def auth_error(conn, {type, _reason}, _opts) do
    :telemetry.execute([:milos, :auth, :anomaly], %{count: 1}, %{reason: reason_label(type)})

    conn
    |> put_status(:unauthorized)
    |> json(%{code: "unauthorized", error: "Unauthorized"})
  end

  defp reason_label(type) when type in @known_types, do: Atom.to_string(type)
  defp reason_label(_type), do: "guardian_other"
end
