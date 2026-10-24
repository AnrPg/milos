defmodule PaleeWeb.GuideProgressControllerTest do
  @moduledoc "ADR-193 over HTTP: `/api/me/guides`, the caller's own progress only."

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  setup %{conn: conn} do
    %{conn: conn, member: user_fixture(), other: user_fixture()}
  end

  defp authed(ctx, user), do: ctx.conn |> recycle() |> put_bearer_token(user)

  test "records steps, a finish and a replay, the caller's own only", ctx do
    assert %{"guides" => []} =
             ctx |> authed(ctx.member) |> get("/api/me/guides") |> json_response(200)

    started =
      ctx
      |> authed(ctx.member)
      |> put("/api/me/guides/shop_staff", %{"status" => "started", "step" => 2})
      |> json_response(200)

    assert %{"guide_id" => "shop_staff", "status" => "started", "step" => 2, "runs" => 1} =
             started

    done =
      ctx
      |> authed(ctx.member)
      |> put("/api/me/guides/shop_staff", %{"status" => "completed", "step" => 7})
      |> json_response(200)

    assert done["completed_at"]

    replay =
      ctx
      |> authed(ctx.member)
      |> put("/api/me/guides/shop_staff", %{"status" => "started"})
      |> json_response(200)

    assert %{"runs" => 2, "completed_at" => nil} = replay

    assert %{"guides" => [%{"guide_id" => "shop_staff"}]} =
             ctx |> authed(ctx.member) |> get("/api/me/guides") |> json_response(200)

    assert %{"guides" => []} =
             ctx |> authed(ctx.other) |> get("/api/me/guides") |> json_response(200)

    assert %{"guides" => []} =
             ctx
             |> authed(ctx.member)
             |> delete("/api/me/guides/shop_staff")
             |> json_response(200)
  end

  test "refuses a bad change or guide id", ctx do
    body =
      ctx
      |> authed(ctx.member)
      |> put("/api/me/guides/shop_staff", %{"status" => "finished", "step" => -1})
      |> json_response(422)

    assert %{"code" => "validation_failed", "errors" => %{"status" => _, "step" => _}} = body

    assert ctx
           |> authed(ctx.member)
           |> put("/api/me/guides/Not-A-Guide", %{"status" => "started"})
           |> json_response(404)
  end

  test "needs a session", ctx do
    assert ctx.conn |> get("/api/me/guides") |> json_response(401)
  end
end
