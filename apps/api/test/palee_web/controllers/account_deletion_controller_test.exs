defmodule PaleeWeb.AccountDeletionControllerTest do
  @moduledoc "ADR-211: the self-service account deletion endpoints."
  use PaleeWeb.ConnCase, async: false
  import Palee.EmailCase

  alias Palee.Identity
  alias Palee.Infrastructure.Security.{MemoryRateLimiter, MemoryTokenStore}

  @password "1537secret"

  setup do
    MemoryRateLimiter.reset!()
    MemoryTokenStore.reset!()
    unique = System.unique_integer([:positive])
    email = "leaver_#{unique}@placeholder.invalid"

    %{"access_token" => token} =
      json_response(
        post_json(build_conn(), "/api/auth/register", %{
          handle: "leaver#{unique}",
          password: @password,
          role: "member",
          email: email
        }),
        201
      )

    %{token: token, email: email, handle: "leaver#{unique}"}
  end

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp authed(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  defp verify!(email) do
    login = Identity.find_login_by_email(email)
    :ok = Identity.mark_email_verified(login.id, email)
  end

  defp link_token(email) do
    message = assert_email_enqueued(kind: :account_deletion_confirm, to: email)
    [_, token] = Regex.run(~r/#token=([A-Za-z0-9_-]{43})/, message.text)
    token
  end

  test "shows no request at first", %{token: token} do
    assert %{"status" => "none", "scope" => nil} =
             json_response(get(authed(token), "/api/auth/account-deletion"), 200)
  end

  test "refuses a wrong password and an unknown scope", %{token: token} do
    conn =
      post_json(authed(token), "/api/auth/account-deletion", %{scope: "login", password: "nope"})

    assert %{"code" => "invalid_password"} = json_response(conn, 422)

    conn =
      post_json(authed(token), "/api/auth/account-deletion", %{scope: "all", password: @password})

    assert json_response(conn, 422)
  end

  test "an unverified email confirms by typing it; the session ends", %{
    token: token,
    email: email
  } do
    conn =
      post_json(authed(token), "/api/auth/account-deletion", %{
        scope: "login",
        password: @password,
        confirm_email: "someone@else.invalid"
      })

    assert %{"code" => "confirmation_mismatch"} = json_response(conn, 422)

    conn =
      post_json(authed(token), "/api/auth/account-deletion", %{
        scope: "login",
        password: @password,
        confirm_email: email
      })

    assert %{"status" => "scheduled", "scope" => "login", "scheduled_for" => at, "email" => nil} =
             json_response(conn, 202)

    assert {:ok, _at, 0} = DateTime.from_iso8601(at)
    assert get(authed(token), "/api/auth/me").status == 401

    conn = post_json(build_conn(), "/api/auth/login", %{identifier: email, password: @password})

    assert %{"code" => "account_deletion_scheduled", "scheduled_for" => ^at} =
             json_response(conn, 403)

    # Wrong credentials say only that.
    conn = post_json(build_conn(), "/api/auth/login", %{identifier: email, password: "nope"})
    assert %{"code" => "invalid_credentials"} = json_response(conn, 401)

    conn =
      post_json(build_conn(), "/api/auth/account-deletion/undo-sign-in", %{
        identifier: email,
        password: "nope"
      })

    assert json_response(conn, 401)

    conn =
      post_json(build_conn(), "/api/auth/account-deletion/undo-sign-in", %{
        identifier: email,
        password: @password
      })

    assert %{"access_token" => fresh, "user" => %{"email" => ^email}} = json_response(conn, 200)
    assert conn.resp_cookies["palee_refresh"]

    assert %{"status" => "none"} =
             json_response(get(authed(fresh), "/api/auth/account-deletion"), 200)
  end

  test "a verified email gets the link; opening it schedules the deletion",
       %{token: token, email: email} do
    verify!(email)

    conn =
      post_json(authed(token), "/api/auth/account-deletion", %{
        scope: "login",
        password: @password
      })

    assert %{"status" => "awaiting_confirmation", "scope" => "login", "email" => ^email} =
             json_response(conn, 202)

    assert %{"status" => "awaiting_confirmation"} =
             json_response(get(authed(token), "/api/auth/account-deletion"), 200)

    raw = link_token(email)

    conn = post_json(build_conn(), "/api/auth/account-deletion/confirm", %{token: raw})
    assert %{"status" => "scheduled", "scope" => "login"} = json_response(conn, 200)

    conn = post_json(build_conn(), "/api/auth/account-deletion/confirm", %{token: raw})
    assert %{"code" => "invalid_deletion_link"} = json_response(conn, 422)

    conn =
      post_json(build_conn(), "/api/auth/account-deletion/undo", %{
        token: String.duplicate("a", 43)
      })

    assert %{"code" => "invalid_deletion_link"} = json_response(conn, 422)
  end

  test "a sole owner of a business is told which one", %{token: token, email: email} do
    account = Identity.find_by_email(email)
    {organization, _owner, _context} = Palee.AnalyticsHelpers.organization_fixture(account)

    conn =
      post_json(authed(token), "/api/auth/account-deletion", %{
        scope: "login",
        password: @password
      })

    assert %{"code" => "sole_owner", "organizations" => [name]} = json_response(conn, 409)
    assert name == organization.name
  end

  test "a signed-in profile can drop a pending request", %{token: token, email: email} do
    verify!(email)
    assert get(authed(token), "/api/auth/account-deletion").status == 200
    assert json_response(delete(authed(token), "/api/auth/account-deletion"), 404)

    post_json(authed(token), "/api/auth/account-deletion", %{scope: "login", password: @password})
    assert response(delete(authed(token), "/api/auth/account-deletion"), 204)

    assert %{"status" => "none"} =
             json_response(get(authed(token), "/api/auth/account-deletion"), 200)
  end
end
