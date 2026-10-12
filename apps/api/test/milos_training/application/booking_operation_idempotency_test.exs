defmodule MilosTraining.Application.BookingOperationIdempotencyTest do
  @moduledoc """
  ADR-120 integration tests: booking request and admin resolution replays
  dedupe on a client operation id, scoped per tenant and requesting user.
  """
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.Application.{ResolveBooking, SubmitBooking}
  alias MilosTraining.Organizations
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workers.{BookingTimeoutJob, ReconcileBookingReleaseJob}
  alias Oban.Testing

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    :ok
  end

  defp organization_fixture do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Replay Gym #{System.unique_integer([:positive])}"
      })

    owner_context = join_organization(organization, owner, :owner)
    {organization, owner, owner_context}
  end

  defp join_organization(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end

  defp slot_fixture(owner, owner_context, attrs \\ %{}) do
    class_type = TestFixtures.class_type_fixture(%{tenant_context: owner_context})
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: owner_context})

    TestFixtures.slot_fixture(
      workout,
      Map.merge(%{tenant_context: owner_context, class_type_id: class_type.id}, attrs)
    )
  end

  defp op, do: Ecto.UUID.generate()

  describe "booking request replay" do
    test "returns the original booking without a second reservation, job, or notification" do
      Testing.with_testing_mode(:manual, fn ->
        {organization, owner, owner_context} = organization_fixture()
        member = TestFixtures.user_fixture()
        context = join_organization(organization, member, :member)
        slot = slot_fixture(owner, owner_context)
        operation_id = op()

        assert {:ok, booking, :created} =
                 SubmitBooking.call(context, member, slot.id, client_operation_id: operation_id)

        assert booking.status == :pending
        assert booking.client_operation_id == operation_id
        notifications_after_first = length(all_enqueued(queue: :notifications))
        assert notifications_after_first > 0

        assert {:ok, replay, :replayed} =
                 SubmitBooking.call(context, member, slot.id, client_operation_id: operation_id)

        assert replay.id == booking.id
        assert length(all_enqueued(worker: BookingTimeoutJob)) == 1
        assert length(all_enqueued(queue: :notifications)) == notifications_after_first
      end)
    end

    test "replays an auto-approved booking" do
      {organization, owner, owner_context} = organization_fixture()
      member = TestFixtures.user_fixture()
      context = join_organization(organization, member, :member)
      slot = slot_fixture(owner, owner_context, %{auto_approve: true})
      operation_id = op()

      assert {:ok, %{status: :approved} = booking, :created} =
               SubmitBooking.call(context, member, slot.id, client_operation_id: operation_id)

      assert {:ok, %{id: id}, :replayed} =
               SubmitBooking.call(context, member, slot.id, client_operation_id: operation_id)

      assert id == booking.id
    end

    test "reusing an operation id for another class is a deterministic conflict" do
      {organization, owner, owner_context} = organization_fixture()
      member = TestFixtures.user_fixture()
      context = join_organization(organization, member, :member)
      first_slot = slot_fixture(owner, owner_context)
      second_slot = slot_fixture(owner, owner_context)
      operation_id = op()

      assert {:ok, _booking, :created} =
               SubmitBooking.call(context, member, first_slot.id,
                 client_operation_id: operation_id
               )

      assert {:error, :idempotency_key_conflict} =
               SubmitBooking.call(context, member, second_slot.id,
                 client_operation_id: operation_id
               )
    end

    test "a second request for the same class with a new operation id stays already_booked" do
      {organization, owner, owner_context} = organization_fixture()
      member = TestFixtures.user_fixture()
      context = join_organization(organization, member, :member)
      slot = slot_fixture(owner, owner_context)

      assert {:ok, _booking, :created} =
               SubmitBooking.call(context, member, slot.id, client_operation_id: op())

      assert {:error, :already_booked} =
               SubmitBooking.call(context, member, slot.id, client_operation_id: op())
    end

    test "rejects a malformed operation id" do
      {organization, owner, owner_context} = organization_fixture()
      member = TestFixtures.user_fixture()
      context = join_organization(organization, member, :member)
      slot = slot_fixture(owner, owner_context)

      assert {:error, [client_operation_id: _]} =
               SubmitBooking.call(context, member, slot.id, client_operation_id: "nope")
    end

    test "operation ids are scoped per tenant" do
      {organization_a, owner_a, owner_context_a} = organization_fixture()
      {organization_b, owner_b, owner_context_b} = organization_fixture()
      member = TestFixtures.user_fixture()
      context_a = join_organization(organization_a, member, :member)
      context_b = join_organization(organization_b, member, :member)
      slot_a = slot_fixture(owner_a, owner_context_a)
      slot_b = slot_fixture(owner_b, owner_context_b)
      operation_id = op()

      assert {:ok, booking_a, :created} =
               SubmitBooking.call(context_a, member, slot_a.id, client_operation_id: operation_id)

      # The same id in another tenant neither replays nor conflicts with tenant A.
      assert {:ok, booking_b, :created} =
               SubmitBooking.call(context_b, member, slot_b.id, client_operation_id: operation_id)

      refute booking_a.id == booking_b.id
      assert booking_b.organization_id == organization_b.id

      assert MilosTraining.Scheduling.get_booking_by_client_operation(
               context_b,
               member.id,
               operation_id
             ).id == booking_b.id
    end
  end

  describe "admin resolution replay" do
    setup do
      {organization, owner, owner_context} = organization_fixture()
      member = TestFixtures.user_fixture()
      context = join_organization(organization, member, :member)
      slot = slot_fixture(owner, owner_context)
      {:ok, booking} = SubmitBooking.call(context, member, slot.id)

      %{owner_context: owner_context, booking: booking}
    end

    test "replaying an approval returns the booking without notifying again", %{
      owner_context: owner_context,
      booking: booking
    } do
      Testing.with_testing_mode(:manual, fn ->
        operation_id = op()
        params = %{action: :approve, admin_message: "See you", client_operation_id: operation_id}

        assert {:ok, approved, :resolved} = ResolveBooking.call(owner_context, booking.id, params)
        assert approved.status == :approved
        assert approved.resolution_operation_id == operation_id
        notifications = length(all_enqueued(queue: :notifications))
        assert notifications > 0

        assert {:ok, replay, :replayed} = ResolveBooking.call(owner_context, booking.id, params)
        assert replay.id == booking.id
        assert replay.status == :approved
        assert length(all_enqueued(queue: :notifications)) == notifications
      end)
    end

    test "reusing the operation id for the opposite outcome is a conflict", %{
      owner_context: owner_context,
      booking: booking
    } do
      operation_id = op()

      assert {:ok, _approved, :resolved} =
               ResolveBooking.call(owner_context, booking.id, %{
                 action: :approve,
                 client_operation_id: operation_id
               })

      assert {:error, :idempotency_key_conflict} =
               ResolveBooking.call(owner_context, booking.id, %{
                 action: :reject,
                 client_operation_id: operation_id
               })
    end

    test "a booking resolved by another operation is never replayed", %{
      owner_context: owner_context,
      booking: booking
    } do
      assert {:ok, _approved, :resolved} =
               ResolveBooking.call(owner_context, booking.id, %{
                 action: :approve,
                 client_operation_id: op()
               })

      assert {:error, :booking_not_pending} =
               ResolveBooking.call(owner_context, booking.id, %{
                 action: :approve,
                 client_operation_id: op()
               })

      assert {:error, :booking_not_pending} =
               ResolveBooking.call(owner_context, booking.id, %{action: :approve})
    end

    test "a rejection replay does not enqueue another release", %{
      owner_context: owner_context,
      booking: booking
    } do
      Testing.with_testing_mode(:manual, fn ->
        params = %{action: :reject, client_operation_id: op()}

        assert {:ok, %{status: :rejected}, :resolved} =
                 ResolveBooking.call(owner_context, booking.id, params)

        releases = length(all_enqueued(worker: ReconcileBookingReleaseJob))
        assert releases > 0

        assert {:ok, %{status: :rejected}, :replayed} =
                 ResolveBooking.call(owner_context, booking.id, params)

        assert length(all_enqueued(worker: ReconcileBookingReleaseJob)) == releases
      end)
    end

    test "another tenant cannot resolve or replay the booking", %{booking: booking} do
      {_organization, _owner, other_owner_context} = organization_fixture()

      assert {:error, :not_found} =
               ResolveBooking.call(other_owner_context, booking.id, %{
                 action: :approve,
                 client_operation_id: op()
               })
    end
  end
end
