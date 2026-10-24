defmodule PaleeWeb.ProfilePRsControllerTest do
  @moduledoc """
  ADR-196: a PR is on its owner's profile for followers or private, and
  Εγώ › Κοινοποίηση's defaults and opt-ins. Runs under the RLS-enforcing
  role (ConnCase default), so the follower read policy is what admits rows.
  """

  use PaleeWeb.ConnCase, async: true

  import Palee.TestFixtures

  defp as(user), do: build_conn() |> put_bearer_token(user)

  defp create_pr!(user, name) do
    as(user)
    |> post("/api/prs", %{
      "name" => name,
      "current_score" => 100,
      "unit" => "kg",
      "beaten_on" => Date.to_iso8601(Date.utc_today())
    })
    |> json_response(201)
    |> get_in(["pr", "id"])
  end

  defp follow!(follower, target) do
    assert %{"status" => "requested"} =
             as(follower)
             |> put_req_header("content-type", "application/json")
             |> post(
               "/api/me/follows",
               Jason.encode!(%{target_type: "user", target_id: target.id})
             )
             |> json_response(200)

    %{"entries" => [%{"follow_id" => follow_id}]} =
      as(target) |> get("/api/me/follow-requests") |> json_response(200)

    as(target) |> post("/api/me/follow-requests/#{follow_id}/accept") |> response(204)
  end

  defp profile_names(reader, owner) do
    as(reader)
    |> get("/api/prs/profile/#{owner.id}")
    |> json_response(200)
    |> Map.fetch!("prs")
    |> Enum.map(& &1["name"])
  end

  test "new PRs are private; followers see only the PRs put on the profile" do
    owner = user_fixture()
    follower = user_fixture()
    stranger = user_fixture()
    follow!(follower, owner)

    squat = create_pr!(owner, "Back Squat")
    _fran = create_pr!(owner, "Fran")

    assert %{"prs" => prs} = as(owner) |> get("/api/prs") |> json_response(200)
    assert Enum.all?(prs, &(&1["profile_audience"] == "private"))
    assert profile_names(follower, owner) == []

    assert %{"pr" => %{"profile_audience" => "followers"}} =
             as(owner)
             |> put("/api/prs/#{squat}/profile-audience", %{"audience" => "followers"})
             |> json_response(200)

    assert profile_names(owner, owner) == ["Back Squat"]
    assert profile_names(follower, owner) == ["Back Squat"]
    assert profile_names(stranger, owner) == []

    # Someone else's PR cannot be moved, and only the two audiences exist.
    assert as(follower)
           |> put("/api/prs/#{squat}/profile-audience", %{"audience" => "private"})
           |> json_response(404)

    assert as(owner)
           |> put("/api/prs/#{squat}/profile-audience", %{"audience" => "public"})
           |> json_response(422)

    assert as(owner) |> get("/api/prs/profile/not-a-uuid") |> json_response(404)
  end

  test "default visibility for new entries, per kind" do
    user = user_fixture()

    assert %{"defaults" => %{"workout" => "coach_can_view", "note" => "private"}} =
             as(user) |> get("/api/me/journal/visibility-defaults") |> json_response(200)

    assert %{"defaults" => %{"note" => "coach_can_view", "check_in" => "private"}} =
             as(user)
             |> put("/api/me/journal/visibility-defaults", %{
               "kind" => "note",
               "visibility" => "coach_can_view"
             })
             |> json_response(200)

    # The PR default is the coach switch on the same page (it moves PRs too).
    assert as(user)
           |> put("/api/me/journal/visibility-defaults", %{
             "kind" => "pr",
             "visibility" => "private"
           })
           |> json_response(422)

    assert as(user)
           |> put("/api/me/journal/visibility-defaults", %{
             "kind" => "workout",
             "visibility" => "posted"
           })
           |> json_response(422)
  end

  test "PR celebrations and challenge rankings opt-ins" do
    user = user_fixture()

    assert %{"preferences" => %{"pr_celebrations" => false, "challenge_rankings" => true}} =
             as(user) |> get("/api/gamification/preferences") |> json_response(200)

    assert %{
             "preferences" => %{
               "pr_celebrations" => true,
               "challenge_rankings" => false,
               "off_days" => []
             }
           } =
             as(user)
             |> put("/api/gamification/preferences", %{
               "pr_celebrations" => true,
               "challenge_rankings" => false
             })
             |> json_response(200)
  end
end
