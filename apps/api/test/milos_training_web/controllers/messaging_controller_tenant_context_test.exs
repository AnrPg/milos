defmodule MilosTrainingWeb.MessagingControllerTenantContextTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Organizations

  test "a non-legacy organization member can create a thread, send a message, and read it back",
       %{conn: conn} do
    owner = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    {:ok, organization} = Organizations.create_organization(%{name: "Messaging Tenant Gym"})

    {:ok, _owner_membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, _athlete_membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: athlete.id,
        role: :athlete,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    create_response =
      conn
      |> put_bearer_token(owner)
      |> post("/api/org/#{organization.slug}/me/threads", %{
        context_type: "direct",
        participant_id: athlete.id
      })
      |> json_response(200)

    thread_id = create_response["thread"]["id"]
    assert thread_id

    send_response =
      conn
      |> put_bearer_token(owner)
      |> post("/api/org/#{organization.slug}/me/threads/#{thread_id}/messages", %{
        body: "Welcome to the gym!"
      })
      |> json_response(201)

    assert send_response["message"]["body"] == "Welcome to the gym!"

    list_response =
      conn
      |> put_bearer_token(athlete)
      |> get("/api/org/#{organization.slug}/me/threads")
      |> json_response(200)

    thread_ids = Enum.map(list_response["threads"], & &1["id"])
    assert thread_id in thread_ids
  end
end
