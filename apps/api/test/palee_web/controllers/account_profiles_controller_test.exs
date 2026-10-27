defmodule PaleeWeb.AccountProfilesControllerTest do
  @moduledoc "ADR-187: one login per email, up to three profiles, sign-in by email or @handle."
  use PaleeWeb.ConnCase, async: false

  alias Palee.Infrastructure.Security.{MemoryRateLimiter, MemoryTokenStore}

  setup do
    MemoryRateLimiter.reset!()
    MemoryTokenStore.reset!()
    :ok
  end

  defp register(params) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/api/auth/register", Jason.encode!(params))
  end

  defp login(params) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/api/auth/login", Jason.encode!(params))
  end

  defp authed(token) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
  end

  @base %{password: "1537", role: "athlete", email: "tolaras@placeholder.invalid"}

  test "a repeat email with another password learns only the count", _ctx do
    assert %{"access_token" => _} =
             json_response(
               register(Map.merge(@base, %{handle: "tolaras", display_name: "Τολάρας"})),
               201
             )

    conn = register(Map.merge(@base, %{handle: "tolaras_two", password: "9999"}))

    assert %{"code" => "email_in_use", "profile_count" => 1, "profile_limit" => 3} =
             json_response(conn, 409)

    refute conn.resp_body =~ ~s("tolaras")
  end

  test "the same email and password add profiles up to three, then stop" do
    for handle <- ~w(tolaras tolaras_coach tolaras_dance) do
      assert %{"access_token" => _} =
               json_response(register(Map.put(@base, :handle, handle)), 201)
    end

    assert %{"code" => "profile_limit", "profile_limit" => 3} =
             json_response(register(Map.put(@base, :handle, "tolaras_four")), 422)
  end

  test "sign-in by email opens the last used profile; by @handle opens that one" do
    json_response(register(Map.merge(@base, %{handle: "tolaras", display_name: "Τολάρας"})), 201)
    json_response(register(Map.put(@base, :handle, "tolaras_coach")), 201)

    assert %{"user" => %{"handle" => "tolaras_coach", "profile_count" => 2}} =
             json_response(
               login(%{identifier: "TOLARAS@placeholder.invalid", password: "1537"}),
               200
             )

    assert %{"user" => %{"handle" => "tolaras", "display_name" => "Τολάρας"}} =
             json_response(login(%{identifier: "@Tolaras", password: "1537"}), 200)

    # Legacy clients still send `nickname`.
    assert %{"user" => %{"handle" => "tolaras"}} =
             json_response(login(%{nickname: "tolaras", password: "1537"}), 200)

    assert json_response(login(%{identifier: "tolaras", password: "nope"}), 401)
  end

  test "a session lists, adds and switches profiles of its own login only" do
    %{"access_token" => token} =
      json_response(register(Map.merge(@base, %{handle: "tolaras"})), 201)

    other =
      json_response(
        register(%{
          handle: "stranger",
          password: "1537",
          role: "member",
          email: "s@placeholder.invalid"
        }),
        201
      )

    assert %{"profiles" => [%{"handle" => "tolaras", "current" => true}], "profile_limit" => 3} =
             json_response(get(authed(token), "/api/auth/profiles"), 200)

    assert %{"profiles" => profiles} =
             json_response(
               post(
                 authed(token),
                 "/api/auth/profiles",
                 Jason.encode!(%{handle: "tolaras_pt", role: "member"})
               ),
               201
             )

    assert %{"id" => pt_id, "current" => false} =
             Enum.find(profiles, &(&1["handle"] == "tolaras_pt"))

    conn = post(authed(token), "/api/auth/switch-profile", Jason.encode!(%{user_id: pt_id}))
    assert %{"access_token" => _, "user" => %{"id" => ^pt_id}} = json_response(conn, 200)
    assert conn.resp_cookies["palee_refresh"]

    %{"access_token" => other_token} = other
    {:ok, claims} = Palee.Infrastructure.Auth.Guardian.decode_and_verify(other_token)

    assert json_response(
             post(
               authed(token),
               "/api/auth/switch-profile",
               Jason.encode!(%{user_id: claims["sub"]})
             ),
             404
           )
  end

  test "handle availability folds what was typed and offers alternatives" do
    json_response(register(Map.put(@base, :handle, "tolaras")), 201)

    assert %{"available" => false, "handle" => "tolaras", "suggestions" => [_ | _]} =
             json_response(get(build_conn(), "/api/auth/handle-available?handle=Τολάρας"), 200)

    assert %{"available" => true, "handle" => "anna.k"} =
             json_response(get(build_conn(), "/api/auth/handle-available?handle=Anna.K"), 200)

    assert %{"handle" => "anna_maria"} =
             json_response(
               get(build_conn(), "/api/auth/handle-suggestion?display_name=Άννα Μαρία"),
               200
             )

    assert %{"handle" => nil} =
             json_response(get(build_conn(), "/api/auth/handle-suggestion?display_name=小明"), 200)
  end

  test "changing the password on one profile signs every profile out" do
    %{"access_token" => first} = json_response(register(Map.put(@base, :handle, "tolaras")), 201)

    %{"access_token" => second} =
      json_response(register(Map.put(@base, :handle, "tolaras_pt")), 201)

    assert json_response(
             patch(
               authed(second),
               "/api/me/profile",
               Jason.encode!(%{password: "4321", current_password: "1537"})
             ),
             200
           )

    assert json_response(get(authed(first), "/api/auth/me"), 401)

    assert %{"user" => %{"handle" => "tolaras"}} =
             json_response(login(%{identifier: "tolaras", password: "4321"}), 200)
  end
end
