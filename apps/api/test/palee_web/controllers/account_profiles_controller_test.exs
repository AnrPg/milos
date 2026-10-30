defmodule PaleeWeb.AccountProfilesControllerTest do
  @moduledoc "ADR-187: one login per email, up to three profiles, sign-in by email or @handle."
  use PaleeWeb.ConnCase, async: false
  import Palee.EmailCase

  alias Palee.Infrastructure.Security.{MemoryRateLimiter, MemoryTokenStore}

  setup do
    MemoryRateLimiter.reset!()
    MemoryTokenStore.reset!()
    :ok
  end

  defp register(params) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/api/auth/register", Jason.encode!(with_age_confirmed(params)))
  end

  # ADR-267: every sign-up confirms the minimum age.
  defp with_age_confirmed(params) when is_map(params) do
    if Enum.any?(Map.keys(params), &is_binary/1),
      do: Map.put_new(params, "age_confirmed", true),
      else: Map.put_new(params, :age_confirmed, true)
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

  describe "ADR-211: a repeat email with another password" do
    setup do
      first = register(Map.merge(@base, %{handle: "tolaras", display_name: "Τολάρας"}))

      assert %{"access_token" => _, "confirmation" => "email_sent", "email" => email} =
               json_response(first, 201)

      assert email == @base.email
      assert first.resp_cookies["palee_refresh"]
      :ok
    end

    test "is answered like a new sign-up, creates nothing and tells the owner" do
      conn = register(Map.merge(@base, %{handle: "tolaras_two", password: "9999"}))

      assert json_response(conn, 201) == %{
               "confirmation" => "email_sent",
               "email" => "tolaras@placeholder.invalid"
             }

      refute conn.resp_cookies["palee_refresh"]
      refute conn.resp_body =~ "tolaras\""
      assert Palee.Identity.find_by_handle("tolaras_two") == nil

      login = Palee.Identity.find_login_by_email(@base.email)
      assert login.profile_count == 1

      email =
        assert_email_enqueued(
          kind: :signup_attempt_existing,
          to: "tolaras@placeholder.invalid",
          category: :account,
          login_id: login.id
        )

      assert email.text =~ "Someone tried to create a Palee account with this email address."
      assert email.text =~ "/login"
      assert email.text =~ "/forgot-password"
      # The email follows the existing profile's language, not the form's.
      refute email.text =~ "Τολάρας"
    end

    test "an email in another case is the same login" do
      conn =
        register(
          Map.merge(@base, %{
            handle: "tolaras_two",
            password: "9999",
            email: "TOLARAS@placeholder.invalid"
          })
        )

      assert %{"confirmation" => "email_sent", "email" => "tolaras@placeholder.invalid"} =
               json_response(conn, 201)

      refute Map.has_key?(json_response(conn, 201), "access_token")
    end

    test "is throttled quietly: the answer stays the same" do
      for _attempt <- 1..3 do
        conn = register(Map.merge(@base, %{handle: "tolaras_two", password: "9999"}))
        assert %{"confirmation" => "email_sent"} = json_response(conn, 201)
      end

      assert length(enqueued_emails(kind: :signup_attempt_existing)) == 1
    end

    test "gets the same field checks a new sign-up gets" do
      # A handle that is taken, as for a new email.
      conn = register(Map.merge(@base, %{handle: "tolaras", password: "9999"}))
      assert %{"errors" => %{"handle" => [_ | _]}} = json_response(conn, 422)

      fresh =
        register(Map.merge(@base, %{handle: "tolaras", email: "someone@placeholder.invalid"}))

      assert %{"errors" => %{"handle" => [_ | _]}} = json_response(fresh, 422)

      # A password too weak to be anyone's.
      weak = register(Map.merge(@base, %{handle: "tolaras_two", password: "  ab  "}))
      assert %{"errors" => %{"password" => [_ | _]}} = json_response(weak, 422)

      refute_email_enqueued(kind: :signup_attempt_existing)
    end

    test "the right password still adds a profile and signs in" do
      conn = register(Map.merge(@base, %{handle: "tolaras_two"}))
      assert %{"access_token" => _, "confirmation" => "email_sent"} = json_response(conn, 201)
      assert Palee.Identity.find_login_by_email(@base.email).profile_count == 2
      refute_email_enqueued(kind: :signup_attempt_existing)
    end
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
