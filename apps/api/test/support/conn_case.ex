defmodule PaleeWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use PaleeWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use PaleeWeb, :verified_routes

      # TD-046: every request is dispatched as the RLS-enforcing runtime role
      # (see PaleeWeb.RLSEnforcedEndpoint). Set after the verified
      # routes `use`, which assigns its own @endpoint.
      @endpoint PaleeWeb.RLSEnforcedEndpoint

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import PaleeWeb.ConnCase
      import Palee.DataCase, only: [bypass_rls: 1, gym_today: 0]
    end
  end

  setup tags do
    Palee.DataCase.setup_sandbox(tags)
    PaleeWeb.RLSEnforcedEndpoint.put_enforced(Map.get(tags, :rls_enforced, true))
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def put_bearer_token(conn, user) do
    alias Palee.Infrastructure.Auth.Guardian

    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{"sv" => user.security_version || 1}, token_type: "access")

    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end
end
