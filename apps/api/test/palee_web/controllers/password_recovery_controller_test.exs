defmodule PaleeWeb.PasswordRecoveryControllerTest do
  @moduledoc "ADR-206: the public password reset endpoints answer alike and spend links only on submit."
  use PaleeWeb.ConnCase, async: false
  use Palee.EmailCase
  use Oban.Testing, repo: Palee.Repo

  alias Palee.Identity
  alias Palee.Infrastructure.Security.{MemoryRateLimiter, MemoryTokenStore}
  alias Palee.Workers.PasswordResetRequestJob

  setup do
    MemoryRateLimiter.reset!()
    MemoryTokenStore.reset!()
    :ok
  end

  defp json_conn do
    build_conn() |> put_req_header("content-type", "application/json")
  end

  defp post_json(path, body), do: post(json_conn(), path, Jason.encode!(body))

  defp register(handle, email) do
    %{"access_token" => token} =
      json_response(
        post_json("/api/auth/register", %{
          handle: handle,
          email: email,
          password: "1537",
          role: "athlete",
          age_confirmed: true
        }),
        201
      )

    token
  end

  defp jobs, do: all_enqueued(worker: PasswordResetRequestJob)

  defp run_jobs do
    for job <- jobs(), do: :ok = perform_job(PasswordResetRequestJob, job.args)
  end

  test "every request gets the same answer and only queues a job" do
    register("verified_one", "verified@example.com")
    register("unverified_one", "unverified@example.com")
    [verified] = Identity.list_profiles(Identity.find_by_email("verified@example.com").login_id)
    :ok = Identity.mark_email_verified(verified.login_id, "verified@example.com")

    bodies =
      for body <- [
            %{identifier: "verified@example.com"},
            %{identifier: "@unverified_one"},
            %{identifier: "nobody@example.com"},
            %{identifier: "verified_one", cant_access_email: true, locale: "el"}
          ] do
        conn = post_json("/api/auth/password-reset-requests", body)
        assert get_resp_header(conn, "cache-control") == ["no-store"]
        assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
        {conn.status, conn.resp_body}
      end

    assert Enum.uniq(bodies) == [{202, ~s({"status":"sent"})}]

    # Nothing happened inside the request: the work is in four identical jobs.
    assert length(jobs()) == 4
    assert enqueued_emails(kind: :password_reset) == []

    run_jobs()
    assert_email_enqueued(kind: :password_reset, to: "verified@example.com")
    refute_email_enqueued(kind: :password_reset, to: "unverified@example.com")
    assert length(Palee.Repo.all(Palee.Identity.PasswordResetRequest)) == 2

    # The job args carry an HMAC of the IP, never the IP.
    refute Enum.any?(jobs(), &(inspect(&1.args) =~ "127.0.0.1"))
  end

  test "the emailed link is checked without spending, then signs every device out" do
    access = register("resetter", "resetter@example.com")
    login_id = Identity.find_by_email("resetter@example.com").login_id
    :ok = Identity.mark_email_verified(login_id, "resetter@example.com")

    post_json("/api/auth/password-reset-requests", %{identifier: "resetter"})
    run_jobs()
    message = assert_email_enqueued(kind: :password_reset)
    [_, token] = Regex.run(~r"#token=([A-Za-z0-9_-]+)", message.text)

    assert %{"expires_at" => _} =
             json_response(post_json("/api/auth/password-reset/inspect", %{token: token}), 200)

    assert %{"expires_at" => _} =
             json_response(post_json("/api/auth/password-reset/inspect", %{token: token}), 200)

    me = fn ->
      build_conn() |> put_req_header("authorization", "Bearer " <> access) |> get("/api/auth/me")
    end

    assert json_response(me.(), 200)

    conn = post_json("/api/auth/password-reset", %{token: token, password: "new pass"})
    assert response(conn, 204)
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]

    assert json_response(me.(), 401)

    assert %{"code" => "used_reset_link"} =
             json_response(post_json("/api/auth/password-reset/inspect", %{token: token}), 410)

    assert %{"code" => "used_reset_link"} =
             json_response(
               post_json("/api/auth/password-reset", %{token: token, password: "other"}),
               410
             )

    assert json_response(
             post_json("/api/auth/login", %{identifier: "resetter", password: "new pass"}),
             200
           )
  end

  test "an unknown link is 422" do
    assert %{"code" => "invalid_reset_link"} =
             json_response(post_json("/api/auth/password-reset/inspect", %{token: "x"}), 422)
  end
end
