defmodule MilosTrainingWeb.PRControllerTest do
  @moduledoc """
  Pantheon PR endpoints under the RLS-enforcing runtime role (ConnCase
  default). Before ADR-111 these ran without any ownership scope, so every
  write was rejected by `user_pr_records_owner_policy` in production.
  """

  use MilosTrainingWeb.ConnCase, async: true

  import MilosTraining.TestFixtures

  alias MilosTraining.Organizations

  test "owner creates, lists, updates, reads history, shares and deletes a PR", %{conn: conn} do
    user = user_fixture()

    created =
      conn
      |> put_bearer_token(user)
      |> post("/api/prs", pr_body("Deadlift"))
      |> json_response(201)

    id = created["pr"]["id"]
    assert created["pr"]["name"] == "Deadlift"
    assert created["pr"]["organization_id"] == nil

    assert %{"prs" => [%{"id" => ^id}]} =
             build_conn() |> put_bearer_token(user) |> get("/api/prs") |> json_response(200)

    assert %{"pr" => %{"current_score" => 190.0}} =
             build_conn()
             |> put_bearer_token(user)
             |> patch("/api/prs/#{id}", %{"current_score" => 190, "beaten_on" => today()})
             |> json_response(200)

    assert %{"history" => [%{"score" => 180.0}]} =
             build_conn()
             |> put_bearer_token(user)
             |> get("/api/prs/#{id}/history")
             |> json_response(200)

    assert %{"message" => message} =
             build_conn()
             |> put_bearer_token(user)
             |> post("/api/prs/#{id}/share")
             |> json_response(200)

    assert message =~ "Deadlift"

    assert build_conn() |> put_bearer_token(user) |> delete("/api/prs/#{id}") |> response(204)
  end

  test "a PR records the gym it was achieved in only for the caller's own gyms", %{conn: conn} do
    user = user_fixture()
    {gym, _context} = tenant_fixture(user, "PR Provenance", :member)
    {foreign, _context} = tenant_fixture(user_fixture(), "PR Foreign")

    created =
      conn
      |> put_bearer_token(user)
      |> post("/api/prs", Map.put(pr_body("Clean"), "organization_slug", gym.slug))
      |> json_response(201)

    assert created["pr"]["organization_id"] == gym.id

    assert %{"code" => "pr_organization_unavailable"} =
             build_conn()
             |> put_bearer_token(user)
             |> post("/api/prs", Map.put(pr_body("Jerk"), "organization_slug", foreign.slug))
             |> json_response(422)
  end

  test "sharing settings: opt-out, grant, shared-with-me and revoke", %{conn: conn} do
    owner = user_fixture()
    friend = user_fixture(%{nickname: "pr_share_friend"})

    conn |> put_bearer_token(owner) |> post("/api/prs", pr_body("Row 2k")) |> json_response(201)

    assert %{"coach_visibility" => true, "grants" => []} =
             build_conn()
             |> put_bearer_token(owner)
             |> get("/api/pr-sharing")
             |> json_response(200)

    assert %{"coach_visibility" => false} =
             build_conn()
             |> put_bearer_token(owner)
             |> put("/api/pr-sharing/coach-visibility", %{"coach_visibility" => false})
             |> json_response(200)

    grant =
      build_conn()
      |> put_bearer_token(owner)
      |> post("/api/pr-sharing/grants", %{"grantee_user_id" => friend.id})
      |> json_response(201)

    assert grant["grantee"]["nickname"] == "pr_share_friend"

    assert %{"code" => "cannot_share_prs_with_self"} =
             build_conn()
             |> put_bearer_token(owner)
             |> post("/api/pr-sharing/grants", %{"grantee_user_id" => owner.id})
             |> json_response(422)

    assert %{"shared" => [%{"owner" => %{"id" => owner_id}, "prs" => [%{"name" => "Row 2k"}]}]} =
             build_conn()
             |> put_bearer_token(friend)
             |> get("/api/pr-sharing/shared-with-me")
             |> json_response(200)

    assert owner_id == owner.id

    assert build_conn()
           |> put_bearer_token(friend)
           |> delete("/api/pr-sharing/grants/#{grant["id"]}")
           |> json_response(404)

    assert build_conn()
           |> put_bearer_token(owner)
           |> delete("/api/pr-sharing/grants/#{grant["id"]}")
           |> response(204)

    assert %{"shared" => []} =
             build_conn()
             |> put_bearer_token(friend)
             |> get("/api/pr-sharing/shared-with-me")
             |> json_response(200)
  end

  defp pr_body(name) do
    %{
      "name" => name,
      "current_score" => 180,
      "unit" => "kg",
      "beaten_on" => today(),
      "supporting_metrics" => %{"reps" => 1}
    }
  end

  defp today, do: Date.to_iso8601(Date.utc_today())

  defp tenant_fixture(user, name, role \\ :owner) do
    bypass_rls(fn ->
      {:ok, organization} =
        Organizations.create_organization(%{
          name: "#{name} #{System.unique_integer([:positive])}"
        })

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
      {organization, context}
    end)
  end
end
