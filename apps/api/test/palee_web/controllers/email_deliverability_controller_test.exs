defmodule PaleeWeb.EmailDeliverabilityControllerTest do
  # ADR-212: Brevo's webhook and the one-click unsubscribe link.
  use PaleeWeb.ConnCase, async: false

  import Palee.EmailCase

  alias Palee.Email
  alias Palee.Email.Message
  alias Palee.Repo

  @secret "brevo-webhook-secret-for-tests-0123456789"
  @assigns %{name: "Jo", url: "https://palee.app/x"}

  setup do
    previous = Application.get_env(:palee, :brevo_webhook_secret)
    Application.put_env(:palee, :brevo_webhook_secret, @secret)
    on_exit(fn -> Application.put_env(:palee, :brevo_webhook_secret, previous) end)

    {:ok, message} = Email.enqueue(:sample_notice, "jo@box.test", @assigns)
    1 = deliver_enqueued_emails()
    %{message: Repo.get!(Message, message.id)}
  end

  defp bounce(message),
    do: %{
      "event" => "hard_bounce",
      "email" => message.to_address,
      "message-id" => message.message_id,
      "ts_epoch" => 1_767_225_600_000
    }

  defp post_webhook(conn, body),
    do:
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/webhooks/brevo", Jason.encode!(body))

  describe "POST /api/webhooks/brevo" do
    test "refuses a call without the secret, or with the wrong one", %{
      conn: conn,
      message: message
    } do
      assert %{"code" => "invalid_webhook_secret"} =
               conn |> post_webhook(bounce(message)) |> json_response(401)

      assert build_conn()
             |> put_req_header("authorization", "Bearer wrong-#{@secret}")
             |> post_webhook(bounce(message))
             |> json_response(401)

      assert build_conn()
             |> put_req_header("authorization", "Basic " <> Base.encode64("palee:nope"))
             |> post_webhook(bounce(message))
             |> json_response(401)

      refute Email.suppressed?("jo@box.test")
    end

    test "refuses everything while no secret is configured", %{conn: conn, message: message} do
      Application.put_env(:palee, :brevo_webhook_secret, nil)

      assert %{"code" => "webhook_not_configured"} =
               conn
               |> put_req_header("authorization", "Bearer #{@secret}")
               |> post_webhook(bounce(message))
               |> json_response(503)
    end

    test "accepts the secret as a bearer token, basic password or header, idempotently", %{
      message: message
    } do
      for {header, value} <- [
            {"authorization", "Bearer #{@secret}"},
            {"authorization", "Basic " <> Base.encode64("palee:#{@secret}")},
            {"x-webhook-secret", @secret}
          ] do
        assert %{"applied" => applied, "duplicate" => duplicate} =
                 build_conn()
                 |> put_req_header(header, value)
                 |> post_webhook(bounce(message))
                 |> json_response(200)

        assert applied + duplicate == 1
      end

      assert Repo.get!(Message, message.id).status == "bounced"
      assert Email.suppressed?("jo@box.test")
    end

    test "takes a batch, and answers 400 to what is not an event", %{message: message} do
      delivered = %{bounce(message) | "event" => "delivered"}

      assert %{"applied" => 2} =
               build_conn()
               |> put_req_header("authorization", "Bearer #{@secret}")
               |> post_webhook([bounce(message), delivered])
               |> json_response(200)

      assert %{"code" => "invalid_payload"} =
               build_conn()
               |> put_req_header("authorization", "Bearer #{@secret}")
               |> post_webhook(%{"hello" => "world"})
               |> json_response(400)
    end
  end

  describe "/api/email/unsubscribe/:token" do
    defp token,
      do:
        Email.unsubscribe_url("jo@box.test", :sample_notice, "el")
        |> String.split("/")
        |> List.last()

    test "GET shows a confirmation and unsubscribes nobody", %{conn: conn} do
      conn = get(conn, "/api/email/unsubscribe/#{token()}")

      html = html_response(conn, 200)
      assert html =~ ~s(lang="el")
      assert html =~ "Διακοπή αυτών των email"
      assert html =~ ~s(method="post")
      assert get_resp_header(conn, "content-security-policy") |> hd() =~ "default-src 'none'"
      refute Email.opted_out?("jo@box.test", :sample_notice)
    end

    test "POST (RFC 8058 one-click) unsubscribes", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/api/email/unsubscribe/#{token()}", "List-Unsubscribe=One-Click")

      assert html_response(conn, 200) =~ "Η εγγραφή σου καταργήθηκε"
      assert Email.opted_out?("jo@box.test", :sample_notice)
      refute Email.suppressed?("jo@box.test")
    end

    test "an invalid token is 404 and changes nothing", %{conn: conn} do
      assert conn |> get("/api/email/unsubscribe/nope") |> html_response(404) =~ "not valid"
      assert build_conn() |> post("/api/email/unsubscribe/#{token()}x") |> html_response(404)
      refute Email.opted_out?("jo@box.test", :sample_notice)
    end
  end
end
