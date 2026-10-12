defmodule MilosTrainingWeb.OfflineCommandReplayControllerTest do
  @moduledoc """
  ADR-102 HTTP contract for the explicitly opted-in offline outbox commands:
  member booking request, admin booking approval/rejection, and training-log
  entry creation. Replays converge on the original result; conflicts are
  deterministic 409s the client surfaces instead of replaying.
  """
  use MilosTrainingWeb.ConnCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.{Organizations, TestFixtures}

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    :ok
  end

  defp organization_with_member do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Outbox Gym #{System.unique_integer([:positive])}"
      })

    for {user, role} <- [{owner, :owner}, {member, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {organization, owner, owner_context, member}
  end

  defp slot_fixture(owner, owner_context) do
    class_type = TestFixtures.class_type_fixture(%{tenant_context: owner_context})
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: owner_context})

    TestFixtures.slot_fixture(workout, %{
      tenant_context: owner_context,
      class_type_id: class_type.id,
      auto_approve: false
    })
  end

  defp book(user, organization, body) do
    build_conn()
    |> put_bearer_token(user)
    |> put_req_header("content-type", "application/json")
    |> post("/api/org/#{organization.slug}/bookings", Jason.encode!(body))
  end

  defp resolve(user, organization, booking_id, action, body) do
    build_conn()
    |> put_bearer_token(user)
    |> put_req_header("content-type", "application/json")
    |> patch(
      "/api/org/#{organization.slug}/admin/bookings/#{booking_id}/#{action}",
      Jason.encode!(body)
    )
  end

  describe "POST /bookings" do
    test "replays the same client_operation_id with 200 and the original booking" do
      {organization, owner, owner_context, member} = organization_with_member()
      slot = slot_fixture(owner, owner_context)
      body = %{slot_id: slot.id, client_operation_id: Ecto.UUID.generate()}

      created = book(member, organization, body) |> json_response(201)
      replayed = book(member, organization, body) |> json_response(200)

      assert replayed["booking"]["id"] == created["booking"]["id"]
      assert created["booking"]["client_operation_id"] == body.client_operation_id
    end

    test "reusing the id for another slot is a 409 idempotency_key_conflict" do
      {organization, owner, owner_context, member} = organization_with_member()
      first_slot = slot_fixture(owner, owner_context)
      second_slot = slot_fixture(owner, owner_context)
      operation_id = Ecto.UUID.generate()

      book(member, organization, %{slot_id: first_slot.id, client_operation_id: operation_id})
      |> json_response(201)

      assert %{"code" => "idempotency_key_conflict"} =
               book(member, organization, %{
                 slot_id: second_slot.id,
                 client_operation_id: operation_id
               })
               |> json_response(409)
    end

    test "rejects a malformed client_operation_id" do
      {organization, owner, owner_context, member} = organization_with_member()
      slot = slot_fixture(owner, owner_context)

      conn = book(member, organization, %{slot_id: slot.id, client_operation_id: "nope"})
      assert conn.status == 422
    end

    test "keeps working without an operation id" do
      {organization, owner, owner_context, member} = organization_with_member()
      slot = slot_fixture(owner, owner_context)

      book(member, organization, %{slot_id: slot.id}) |> json_response(201)

      assert %{"code" => "already_booked"} =
               book(member, organization, %{slot_id: slot.id}) |> json_response(409)
    end
  end

  describe "PATCH /admin/bookings/:id/approve|reject" do
    setup do
      {organization, owner, owner_context, member} = organization_with_member()
      slot = slot_fixture(owner, owner_context)
      booking = book(member, organization, %{slot_id: slot.id}) |> json_response(201)

      %{organization: organization, owner: owner, booking_id: booking["booking"]["id"]}
    end

    test "replays the resolving operation and refuses everything else", %{
      organization: organization,
      owner: owner,
      booking_id: booking_id
    } do
      operation_id = Ecto.UUID.generate()
      body = %{admin_message: "Welcome", client_operation_id: operation_id}

      approved = resolve(owner, organization, booking_id, "approve", body) |> json_response(200)
      assert approved["booking"]["status"] == "approved"

      replayed = resolve(owner, organization, booking_id, "approve", body) |> json_response(200)
      assert replayed["booking"]["id"] == booking_id

      assert %{"code" => "idempotency_key_conflict"} =
               resolve(owner, organization, booking_id, "reject", body) |> json_response(409)

      assert %{"code" => "booking_not_pending"} =
               resolve(owner, organization, booking_id, "approve", %{
                 client_operation_id: Ecto.UUID.generate()
               })
               |> json_response(409)

      assert %{"code" => "booking_not_pending"} =
               resolve(owner, organization, booking_id, "reject", %{}) |> json_response(409)
    end

    test "another tenant's admin gets 404 even with a replayed operation id", %{
      booking_id: booking_id
    } do
      {other_organization, other_owner, _context, _member} = organization_with_member()

      assert resolve(other_owner, other_organization, booking_id, "approve", %{
               client_operation_id: Ecto.UUID.generate()
             }).status == 404
    end
  end

  describe "POST /me/training-log/entries" do
    test "reusing an idempotency key for a different source is a 409" do
      {organization, owner, owner_context, member} = organization_with_member()
      slot = slot_fixture(owner, owner_context)
      key = "outbox-" <> Ecto.UUID.generate()

      freeform = %{
        source_type: "freeform",
        title: "Hotel gym",
        performed_at: DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601(),
        idempotency_key: key
      }

      path = "/api/org/#{organization.slug}/me/training-log/entries"

      build_conn() |> put_bearer_token(member) |> post(path, freeform) |> json_response(201)
      build_conn() |> put_bearer_token(member) |> post(path, freeform) |> json_response(200)

      assert %{"code" => "idempotency_key_conflict"} =
               build_conn()
               |> put_bearer_token(member)
               |> post(path, %{
                 source_type: "class",
                 source_reference_id: slot.id,
                 performed_at: freeform.performed_at,
                 idempotency_key: key
               })
               |> json_response(409)
    end
  end
end
