defmodule PaleeWeb.SecurityLinkControllerTest do
  use PaleeWeb.ConnCase, async: true
  use Palee.EmailCase

  alias Palee.Email.LinkTokens
  alias Palee.Identity
  alias Palee.TestFixtures

  setup do
    person = TestFixtures.user_fixture(%{email: "signout@example.com"})

    {:ok, second} =
      Identity.add_profile(person.login_id, %{handle: "second_profile", role: :member})

    %{person: person, second: second}
  end

  defp post_link(conn, token),
    do:
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/auth/sign-out-everywhere", Jason.encode!(%{token: token}))

  test "the emailed link ends the sessions of every profile of the login, once", %{
    conn: conn,
    person: person,
    second: second
  } do
    {:ok, raw, _token} =
      LinkTokens.issue(:sign_out_everywhere, person.login_id,
        user_id: person.id,
        target_email: "signout@example.com"
      )

    before =
      {Identity.find_by_id(person.id).security_version,
       Identity.find_by_id(second.id).security_version}

    assert conn |> post_link(raw) |> response(204)

    assert Identity.find_by_id(person.id).security_version > elem(before, 0)
    assert Identity.find_by_id(second.id).security_version > elem(before, 1)
    # Opening the link proved the address.
    assert Identity.email_verified?(Identity.find_by_id(person.id))

    message = assert_email_enqueued(kind: :security_signed_out_everywhere)
    assert message.text =~ "/forgot-password"
    refute message.text =~ "sign-out-everywhere#token="

    assert %{"code" => "used_link"} = build_conn() |> post_link(raw) |> json_response(410)
  end

  test "an expired, unknown or missing link says so", %{conn: conn, person: person} do
    {:ok, raw, _token} =
      LinkTokens.issue(:sign_out_everywhere, person.login_id,
        now: DateTime.add(DateTime.utc_now(), -8 * 24 * 3600, :second)
      )

    assert %{"code" => "expired_link"} = conn |> post_link(raw) |> json_response(410)

    assert %{"code" => "invalid_link"} =
             build_conn() |> post_link(String.duplicate("a", 43)) |> json_response(422)

    assert %{"code" => "invalid_link"} =
             build_conn()
             |> put_req_header("content-type", "application/json")
             |> post("/api/auth/sign-out-everywhere", "{}")
             |> json_response(422)

    # A password reset link is not a sign-out link.
    {:ok, reset, _} = LinkTokens.issue(:password_reset, person.login_id)
    assert %{"code" => "invalid_link"} = build_conn() |> post_link(reset) |> json_response(422)
  end
end
