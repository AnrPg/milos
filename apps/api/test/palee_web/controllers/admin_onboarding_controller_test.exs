defmodule PaleeWeb.AdminOnboardingControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Identity, Organizations}

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, user} =
      Identity.register(%{
        nickname: "onboarding_owner",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "owner#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, owner} = Identity.update_role(user, :admin)
    {:ok, organization} = Organizations.create_organization(%{name: "Onboarding Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    %{conn: conn, owner: owner, organization: organization}
  end

  defp path(context), do: "/api/org/#{context.organization.slug}/admin/onboarding"
  defp authed(context), do: context.conn |> recycle() |> put_bearer_token(context.owner)

  defp act(context, body) do
    context
    |> authed()
    |> put_req_header("content-type", "application/json")
    |> patch(path(context), Jason.encode!(body))
  end

  test "a new organization sees an open checklist", context do
    checklist = context |> authed() |> get(path(context)) |> json_response(200)

    assert checklist["total"] == 7
    refute checklist["dismissed"]
    refute checklist["finished"]

    assert %{"id" => "invite", "done" => false} =
             Enum.find(checklist["steps"], &(&1["id"] == "invite"))
  end

  test "progress persists and is resumable", context do
    act(context, %{action: "complete", step: "settings"}) |> json_response(200)
    act(context, %{action: "skip", step: "packages"}) |> json_response(200)
    act(context, %{action: "dismiss"}) |> json_response(200)

    checklist = context |> authed() |> get(path(context)) |> json_response(200)
    steps = Map.new(checklist["steps"], &{&1["id"], &1})

    assert steps["settings"]["done"]
    assert steps["packages"]["skipped"]
    assert checklist["dismissed"]

    assert %{"dismissed" => false} = act(context, %{action: "restore"}) |> json_response(200)
  end

  test "inviting a client completes the invite step automatically", context do
    client = user_fixture()

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: context.organization.id,
        user_id: client.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    checklist = context |> authed() |> get(path(context)) |> json_response(200)

    assert %{"done" => true, "auto" => true} =
             Enum.find(checklist["steps"], &(&1["id"] == "invite"))
  end

  test "unknown actions are rejected", context do
    assert %{"code" => "invalid_onboarding_action"} =
             act(context, %{action: "complete", step: "everything"}) |> json_response(422)
  end
end
