defmodule PaleeWeb.InsightsControllerTest do
  @moduledoc """
  ADR-166 over HTTP: `GET /api/me/insights`, `POST /api/me/insights/:rule/
  dismiss` and `POST /api/me/insights/restore`, the caller's own only.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Insights.Insight
  alias Palee.Repo
  alias Palee.Workers.NightlyInsightsJob

  setup %{conn: conn} do
    %{conn: conn, member: user_fixture(), other: user_fixture()}
  end

  defp authed(ctx, user), do: ctx.conn |> recycle() |> put_bearer_token(user)

  # A stored finding computed now, so the read does not recompute.
  defp finding!(user) do
    now = DateTime.utc_now()
    today = Date.utc_today()

    for rule <- ~w(sleep_prs sleep_effort time_of_day cravings hydration) do
      finding? = rule == "time_of_day"

      Repo.insert!(%Insight{
        user_id: user.id,
        rule: rule,
        status: if(finding?, do: "finding", else: "insufficient"),
        period_start: Date.add(today, -83),
        period_end: today,
        value:
          if(finding?,
            do: %{
              "variant" => "best_part",
              "params" => %{"part" => "morning", "ratio" => 1.8},
              "weeks" => 6
            },
            else: %{"weeks" => 6, "sample" => %{}}
          ),
        fingerprint: if(finding?, do: "time_of_day:best_part:morning"),
        computed_at: now
      })
    end
  end

  test "an account without data is still collecting", ctx do
    body = ctx |> authed(ctx.member) |> get("/api/me/insights") |> json_response(200)
    assert body["state"] == "collecting"
    assert body["insights"] == [] and body["min_weeks"] == 4 and body["max_shown"] == 3
    assert body["data_weeks"] == 0
  end

  test "shows, dismisses and restores the caller's own findings", ctx do
    finding!(ctx.member)

    body = ctx |> authed(ctx.member) |> get("/api/me/insights") |> json_response(200)
    assert body["state"] == "insights"

    assert [%{"rule" => "time_of_day", "variant" => "best_part", "weeks" => 6} = insight] =
             body["insights"]

    assert insight["params"] == %{"part" => "morning", "ratio" => 1.8}

    other = ctx |> authed(ctx.other) |> get("/api/me/insights") |> json_response(200)
    assert other["insights"] == []

    assert ctx
           |> authed(ctx.other)
           |> post("/api/me/insights/time_of_day/dismiss")
           |> json_response(404)

    dismissed =
      ctx
      |> authed(ctx.member)
      |> post("/api/me/insights/time_of_day/dismiss")
      |> json_response(200)

    assert dismissed["state"] == "all_hidden" and dismissed["hidden_count"] == 1

    assert ctx
           |> authed(ctx.member)
           |> post("/api/me/insights/stars/dismiss")
           |> json_response(422)

    restored =
      ctx |> authed(ctx.member) |> post("/api/me/insights/restore") |> json_response(200)

    assert restored["state"] == "insights"
  end

  test "needs a session", ctx do
    assert ctx.conn |> get("/api/me/insights") |> json_response(401)
  end

  test "the nightly job runs" do
    assert :ok = perform_job(NightlyInsightsJob, %{})
  end

  defp perform_job(worker, args), do: worker.perform(%Oban.Job{args: args})
end
