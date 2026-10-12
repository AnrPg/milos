defmodule MilosTraining.Application.TrainingLogEntryTest do
  @moduledoc "ADR-100 integration tests: application services + Ecto store."
  use MilosTraining.DataCase, async: false

  import Ecto.Query

  alias MilosTraining.Application.{
    ListTrainingLogEntries,
    ListTrainingLogSources,
    LogTrainingEntry,
    UpdateTrainingLogEntry,
    VoidTrainingLogEntry
  }

  alias MilosTraining.{Execution, Gamification, Organizations, Repo, Scheduling, Workouts}
  alias MilosTraining.Scheduling.ScheduledClass
  alias MilosTraining.TestFixtures

  defp organization_fixture(owner) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "Log Gym #{System.unique_integer([:positive])}"})

    membership_fixture(organization, owner, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {organization, context}
  end

  defp membership_fixture(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp member_context(organization, role \\ :member) do
    user =
      TestFixtures.user_fixture(%{role: if(role == :athlete, do: :athlete, else: :member)})

    membership_fixture(organization, user, role)
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {user, context}
  end

  defp workout_fixture(context, admin, scoreable? \\ false) do
    {:ok, workout} =
      Workouts.create_workout(context, admin, %{
        title: "Logged WOD #{System.unique_integer([:positive])}",
        type: :crossfit,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: scoreable?,
            score_config: if(scoreable?, do: %{type: "time", unit: "seconds"}),
            exercises: [
              %{
                name: "Burpees",
                order: 1,
                sets: 3,
                prescription_value: 10,
                prescription_unit: "reps"
              }
            ]
          }
        ]
      })

    workout
  end

  defp past_class_fixture(context, workout, member) do
    class_type = TestFixtures.class_type_fixture(%{tenant_context: context})

    slot =
      TestFixtures.slot_fixture(workout, %{
        tenant_context: context,
        class_type_id: class_type.id,
        auto_approve: true
      })

    {:ok, booking} = Scheduling.submit_auto_approved_booking(context, member.id, slot.id)

    past = DateTime.add(DateTime.utc_now(), -2 * 3600, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(s in ScheduledClass, where: s.id == ^slot.id), set: [scheduled_at: past])

    {slot, booking}
  end

  defp key, do: "key-" <> Ecto.UUID.generate()

  defp yesterday_iso,
    do: DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.to_iso8601()

  defp freeform_params(overrides \\ %{}) do
    Map.merge(
      %{
        "source_type" => "freeform",
        "title" => "Hotel gym session",
        "performed_at" => yesterday_iso(),
        "duration_seconds" => 1800,
        "perceived_effort" => 6,
        "idempotency_key" => key(),
        "performed_exercises" => [%{"name" => "Push-ups", "sets" => 3, "reps" => 20}]
      },
      overrides
    )
  end

  describe "freeform logging" do
    test "logs, replays idempotently, and counts toward gamification" do
      owner = TestFixtures.admin_fixture()
      {organization, _owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      params = freeform_params()

      assert {:ok, entry, :created} = LogTrainingEntry.call(context, member, params)
      assert entry.source_type == "freeform"
      assert entry.title == "Hotel gym session"
      assert entry.organization_id == organization.id
      assert entry.user_id == member.id
      assert entry.status == "logged"
      assert [%{"name" => "Push-ups"}] = entry.performed_exercises

      assert {:ok, replay, :replayed} = LogTrainingEntry.call(context, member, params)
      assert replay.id == entry.id

      assert %{total_workouts: 1} = Gamification.get_user_stats(member.id)
      assert {:ok, [listed]} = ListTrainingLogEntries.call(context, member)
      assert listed.id == entry.id
    end

    test "rejects a freeform reference, missing title, and client-supplied ownership" do
      owner = TestFixtures.admin_fixture()
      {organization, _owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)

      assert {:error, :invalid_training_log_source} =
               LogTrainingEntry.call(
                 context,
                 member,
                 freeform_params(%{"source_reference_id" => Ecto.UUID.generate()})
               )

      assert {:error, [title: _]} =
               LogTrainingEntry.call(context, member, freeform_params(%{"title" => " "}))

      other_org = Ecto.UUID.generate()

      assert {:ok, entry, :created} =
               LogTrainingEntry.call(
                 context,
                 member,
                 freeform_params(%{"organization_id" => other_org, "user_id" => owner.id})
               )

      assert entry.organization_id == organization.id
      assert entry.user_id == member.id
    end

    test "voided entries stop counting on the next projection" do
      owner = TestFixtures.admin_fixture()
      {organization, _owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)

      {:ok, first, :created} = LogTrainingEntry.call(context, member, freeform_params())
      assert %{total_workouts: 1} = Gamification.get_user_stats(member.id)

      assert {:ok, voided} =
               VoidTrainingLogEntry.call(context, member, first.id, %{"reason" => "duplicate"})

      assert voided.status == "voided"
      assert voided.void_reason == "duplicate"

      {:ok, _second, :created} = LogTrainingEntry.call(context, member, freeform_params())
      assert %{total_workouts: 1} = Gamification.get_user_stats(member.id)
    end
  end

  describe "class logging" do
    test "logs an attended class once, and voiding frees it for a corrected log" do
      owner = TestFixtures.admin_fixture()
      {organization, owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      workout = workout_fixture(owner_context, owner)
      {slot, booking} = past_class_fixture(owner_context, workout, member)

      class_params = %{
        "source_type" => "class",
        "source_reference_id" => slot.id,
        "performed_at" => yesterday_iso(),
        "idempotency_key" => key()
      }

      assert {:ok, %{classes: [candidate]}} = ListTrainingLogSources.call(context, member)
      assert candidate.id == slot.id
      assert candidate.booking_id == booking.id

      assert {:ok, entry, :created} = LogTrainingEntry.call(context, member, class_params)
      assert entry.source_reference_id == slot.id
      assert entry.booking_id == booking.id
      assert entry.master_workout_id == workout.id
      assert entry.workout_type == "crossfit"

      assert {:ok, %{classes: []}} = ListTrainingLogSources.call(context, member)

      assert {:error, :training_log_source_already_logged} =
               LogTrainingEntry.call(context, member, %{class_params | "idempotency_key" => key()})

      assert {:ok, _voided} = VoidTrainingLogEntry.call(context, member, entry.id, %{})

      assert {:ok, _relogged, :created} =
               LogTrainingEntry.call(context, member, %{class_params | "idempotency_key" => key()})
    end

    test "refuses classes the member did not book or that have not started" do
      owner = TestFixtures.admin_fixture()
      {organization, owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      {stranger, stranger_context} = member_context(organization)
      workout = workout_fixture(owner_context, owner)
      {slot, _booking} = past_class_fixture(owner_context, workout, member)

      assert {:error, :training_log_source_forbidden} =
               LogTrainingEntry.call(stranger_context, stranger, %{
                 "source_type" => "class",
                 "source_reference_id" => slot.id,
                 "performed_at" => yesterday_iso(),
                 "idempotency_key" => key()
               })

      future_class_type = TestFixtures.class_type_fixture(%{tenant_context: owner_context})

      future_slot =
        TestFixtures.slot_fixture(workout, %{
          tenant_context: owner_context,
          class_type_id: future_class_type.id,
          auto_approve: true
        })

      {:ok, _booking} =
        Scheduling.submit_auto_approved_booking(owner_context, member.id, future_slot.id)

      assert {:error, :training_log_source_not_started} =
               LogTrainingEntry.call(context, member, %{
                 "source_type" => "class",
                 "source_reference_id" => future_slot.id,
                 "performed_at" => yesterday_iso(),
                 "idempotency_key" => key()
               })
    end

    test "refuses to double count a class already completed as an execution" do
      owner = TestFixtures.admin_fixture()
      {organization, owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      workout = workout_fixture(owner_context, owner)
      {slot, booking} = past_class_fixture(owner_context, workout, member)

      Workouts.with_tenant_context(context, fn ->
        {:ok, execution} =
          Execution.start_execution(member.id, %{
            master_workout_id: workout.id,
            source: :class_booking,
            source_reference_id: booking.id,
            organization_id: organization.id
          })

        {:ok, _completed} = Execution.complete_execution(execution.id, member.id, %{})
      end)

      assert {:error, :training_log_already_counted} =
               LogTrainingEntry.call(context, member, %{
                 "source_type" => "class",
                 "source_reference_id" => slot.id,
                 "performed_at" => yesterday_iso(),
                 "idempotency_key" => key()
               })

      assert {:ok, %{classes: []}} = ListTrainingLogSources.call(context, member)
    end

    test "accepts section scores only for the class workout's scoreable sections" do
      owner = TestFixtures.admin_fixture()
      {organization, owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      workout = workout_fixture(owner_context, owner, true)
      {slot, _booking} = past_class_fixture(owner_context, workout, member)
      [section | _] = workout.sections

      base = %{
        "source_type" => "class",
        "source_reference_id" => slot.id,
        "performed_at" => yesterday_iso()
      }

      assert {:error, [section_scores: _]} =
               LogTrainingEntry.call(
                 context,
                 member,
                 Map.merge(base, %{
                   "idempotency_key" => key(),
                   "section_scores" => [%{"section_id" => Ecto.UUID.generate(), "value" => 1}]
                 })
               )

      assert {:ok, entry, :created} =
               LogTrainingEntry.call(
                 context,
                 member,
                 Map.merge(base, %{
                   "idempotency_key" => key(),
                   "section_scores" => [%{"section_id" => section.id, "value" => 300}]
                 })
               )

      assert [%{"section_id" => section_id, "value" => 300}] = entry.section_scores
      assert section_id == section.id
    end
  end

  describe "assigned and library sources" do
    test "athletes log their own assignment; others cannot; athletes cannot self-select" do
      owner = TestFixtures.admin_fixture()
      {organization, owner_context} = organization_fixture(owner)
      {athlete, athlete_context} = member_context(organization, :athlete)
      {other, other_context} = member_context(organization, :athlete)
      workout = workout_fixture(owner_context, owner)

      {:ok, assignment} =
        Workouts.assign_workout(owner_context, %{
          master_workout_id: workout.id,
          athlete_ids: [athlete.id],
          scheduled_for: Date.utc_today()
        })

      assignment_id = assignment.id

      assert {:ok, %{assignments: [%{id: ^assignment_id}], library_workouts: []}} =
               ListTrainingLogSources.call(athlete_context, athlete)

      params = %{
        "source_type" => "assigned_workout",
        "source_reference_id" => assignment_id,
        "performed_at" => yesterday_iso(),
        "idempotency_key" => key()
      }

      assert {:error, :not_found} = LogTrainingEntry.call(other_context, other, params)
      assert {:ok, entry, :created} = LogTrainingEntry.call(athlete_context, athlete, params)
      assert entry.master_workout_id == workout.id
      assert entry.title == workout.title

      assert {:error, :training_log_source_forbidden} =
               LogTrainingEntry.call(athlete_context, athlete, %{
                 "source_type" => "library_workout",
                 "source_reference_id" => workout.id,
                 "performed_at" => yesterday_iso(),
                 "idempotency_key" => key()
               })
    end

    test "members log published library workouts repeatedly" do
      owner = TestFixtures.admin_fixture()
      {organization, owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      workout = workout_fixture(owner_context, owner)

      params = fn ->
        %{
          "source_type" => "library_workout",
          "source_reference_id" => workout.id,
          "performed_at" => yesterday_iso(),
          "idempotency_key" => key()
        }
      end

      assert {:ok, %{library_workouts: library}} = ListTrainingLogSources.call(context, member)
      assert Enum.any?(library, &(&1.id == workout.id))
      assert {:ok, _first, :created} = LogTrainingEntry.call(context, member, params.())
      assert {:ok, _second, :created} = LogTrainingEntry.call(context, member, params.())
    end
  end

  describe "editing" do
    test "owners edit details with optimistic concurrency; voided entries are frozen" do
      owner = TestFixtures.admin_fixture()
      {organization, _owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      {:ok, entry, :created} = LogTrainingEntry.call(context, member, freeform_params())

      assert {:ok, updated} =
               UpdateTrainingLogEntry.call(context, member, entry.id, %{
                 "notes" => "Felt great",
                 "perceived_effort" => 8,
                 "expected_version" => entry.lock_version
               })

      assert updated.notes == "Felt great"
      assert updated.perceived_effort == 8
      assert updated.title == entry.title
      assert updated.lock_version == entry.lock_version + 1

      assert {:error, :stale_training_log_entry} =
               UpdateTrainingLogEntry.call(context, member, entry.id, %{
                 "notes" => "lost update",
                 "expected_version" => entry.lock_version
               })

      assert {:ok, _voided} = VoidTrainingLogEntry.call(context, member, entry.id, %{})

      assert {:error, :training_log_entry_voided} =
               UpdateTrainingLogEntry.call(context, member, entry.id, %{"notes" => "x"})

      assert {:error, :training_log_entry_voided} =
               VoidTrainingLogEntry.call(context, member, entry.id, %{})
    end
  end

  describe "tenant isolation" do
    test "entries are invisible across tenants and to other members" do
      owner_a = TestFixtures.admin_fixture()
      owner_b = TestFixtures.admin_fixture()
      {organization_a, _} = organization_fixture(owner_a)
      {organization_b, _} = organization_fixture(owner_b)
      {member, context_a} = member_context(organization_a)
      membership_fixture(organization_b, member, :member)
      {:ok, context_b} = Organizations.resolve_tenant_context(member, organization_b.slug)
      {peer, peer_context} = member_context(organization_a)

      {:ok, entry, :created} = LogTrainingEntry.call(context_a, member, freeform_params())

      assert {:ok, []} = ListTrainingLogEntries.call(context_b, member)
      assert {:error, :not_found} = ListTrainingLogEntries.get(context_b, member, entry.id)

      assert {:error, :not_found} =
               UpdateTrainingLogEntry.call(context_b, member, entry.id, %{"notes" => "x"})

      assert {:error, :not_found} = VoidTrainingLogEntry.call(context_b, member, entry.id, %{})

      assert {:ok, []} = ListTrainingLogEntries.call(peer_context, peer)
      assert {:error, :not_found} = ListTrainingLogEntries.get(peer_context, peer, entry.id)
      assert {:error, :not_found} = VoidTrainingLogEntry.call(peer_context, peer, entry.id, %{})

      # The same idempotency key is independent per tenant.
      assert {:ok, other_entry, :created} =
               LogTrainingEntry.call(
                 context_b,
                 member,
                 freeform_params(%{"idempotency_key" => entry.idempotency_key})
               )

      refute other_entry.id == entry.id
      assert other_entry.organization_id == organization_b.id
    end

    test "fails closed without a tenant context" do
      member = TestFixtures.user_fixture()

      assert {:error, :organization_context_required} =
               LogTrainingEntry.call(nil, member, freeform_params())

      assert {:error, :organization_context_required} = ListTrainingLogEntries.call(%{}, member)
    end
  end

  describe "offline replay (ADR-102)" do
    test "replays an accepted class log even after the source stopped authorizing" do
      owner = TestFixtures.admin_fixture()
      {organization, owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      workout = workout_fixture(owner_context, owner)
      {slot, booking} = past_class_fixture(owner_context, workout, member)

      class_params = %{
        "source_type" => "class",
        "source_reference_id" => slot.id,
        "performed_at" => yesterday_iso(),
        "idempotency_key" => key()
      }

      assert {:ok, entry, :created} = LogTrainingEntry.call(context, member, class_params)

      Repo.update_all(from(b in MilosTraining.Scheduling.Booking, where: b.id == ^booking.id),
        set: [status: :rejected]
      )

      # A fresh submission is re-authorized and refused...
      assert {:error, :training_log_source_forbidden} =
               LogTrainingEntry.call(context, member, %{class_params | "idempotency_key" => key()})

      # ...but the acknowledged-yet-unconfirmed original converges on its entry.
      assert {:ok, replay, :replayed} = LogTrainingEntry.call(context, member, class_params)
      assert replay.id == entry.id
    end

    test "reusing a key for a different source is a deterministic conflict" do
      owner = TestFixtures.admin_fixture()
      {organization, owner_context} = organization_fixture(owner)
      {member, context} = member_context(organization)
      workout = workout_fixture(owner_context, owner)
      {slot, _booking} = past_class_fixture(owner_context, workout, member)
      params = freeform_params()

      assert {:ok, _entry, :created} = LogTrainingEntry.call(context, member, params)

      assert {:error, :idempotency_key_conflict} =
               LogTrainingEntry.call(context, member, %{
                 "source_type" => "class",
                 "source_reference_id" => slot.id,
                 "performed_at" => yesterday_iso(),
                 "idempotency_key" => params["idempotency_key"]
               })
    end
  end
end
