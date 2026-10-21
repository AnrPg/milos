defmodule Palee.Application.CrossProviderRLSTest do
  @moduledoc """
  ADR-162 under real Row Level Security: a member of a box and of an
  independent coach has one journal, Vault, Πρόοδος and history across
  both; each provider's coach reads only what was done with them or shared
  with them («Οι coach μου»), and a provider the member left loses access
  from that day while the member keeps the history, labelled former.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.Application.{
    GetAccountHistory,
    GetAccountProgress,
    GetAccountVault,
    GetClientJournal,
    GetJournalFeed,
    GetTrainingHistory,
    JournalAudience,
    JournalComments,
    JournalExports,
    JournalNotes,
    MyProviders,
    SetJournalVisibility
  }

  alias Palee.Execution.WorkoutExecution
  alias Palee.Identity.UserContext
  alias Palee.Notifications.Notification
  alias Palee.{Organizations, Repo}

  setup do
    fixtures =
      bypass_rls(fn ->
        box = org!("Box Kypseli", "gym")
        nikos = org!("Nikos PT", "coach")
        box_owner = user_fixture()
        box_coach = user_fixture()
        nikos_owner = user_fixture()
        member = user_fixture()
        add!(box, box_owner, :owner)
        add!(box, box_coach, :coach)
        add!(nikos, nikos_owner, :owner)
        box_membership = add!(box, member, :member)
        add!(nikos, member, :member)

        %{
          box: box,
          nikos: nikos,
          box_owner: box_owner,
          box_coach: box_coach,
          nikos_owner: nikos_owner,
          member: member,
          box_membership: box_membership
        }
      end)

    Map.merge(fixtures, %{member_ctx: UserContext.new(fixtures.member)})
  end

  test "one journal across providers; each coach reads only what reaches them", ctx do
    {:ok, at_box} =
      JournalNotes.create(ctx.member_ctx, %{
        "topic" => "technique",
        "body" => "Box squat depth",
        "organization_slug" => ctx.box.slug
      })

    {:ok, personal} =
      JournalNotes.create(ctx.member_ctx, %{"topic" => "thought", "body" => "Long run thoughts"})

    for note <- [at_box, personal] do
      {:ok, _moved} =
        SetJournalVisibility.call(ctx.member_ctx, "note", note.id, %{
          "visibility" => "coach_can_view"
        })
    end

    # Box coach: the box's note and the personal one (default audience).
    assert coach_sees(ctx.box_coach, ctx.box, ctx.member) |> Enum.sort() ==
             Enum.sort([at_box.id, personal.id])

    # Nikos: only the personal one; never the box's.
    assert coach_sees(ctx.nikos_owner, ctx.nikos, ctx.member) == [personal.id]

    # «Οι coach μου» without Nikos: the personal note leaves him.
    assert {:ok, %{organization_ids: [box_id]}} =
             JournalAudience.put_default(ctx.member_ctx, [ctx.box.id])

    assert box_id == ctx.box.id
    assert coach_sees(ctx.nikos_owner, ctx.nikos, ctx.member) == []

    # Sharing the box's note with Nikos explicitly reaches him.
    assert {:ok, %{audience: %{custom: true, organization_ids: ids}}} =
             JournalAudience.put_entry(ctx.member_ctx, "note", at_box.id, [ctx.nikos.id])

    assert Enum.sort(ids) == Enum.sort([ctx.box.id, ctx.nikos.id])
    assert coach_sees(ctx.nikos_owner, ctx.nikos, ctx.member) == [at_box.id]

    # Narrowing the personal note to Nikos only takes it from the box.
    {:ok, _audience} =
      JournalAudience.put_entry(ctx.member_ctx, "note", personal.id, [ctx.nikos.id])

    assert coach_sees(ctx.box_coach, ctx.box, ctx.member) == [at_box.id]

    assert {:error, :unknown_provider} =
             JournalAudience.put_entry(ctx.member_ctx, "note", personal.id, [Ecto.UUID.generate()])

    # The member's own feed labels each entry and filters by source and text.
    assert {:ok, %{items: items, active_filter_count: 0}} =
             GetJournalFeed.call(ctx.member_ctx, %{})

    assert %{at_box.id => "organization", personal.id => "freeform"} ==
             Map.new(items, &{&1.id, &1.source.kind})

    assert {:ok, %{items: [only], active_filter_count: 1}} =
             GetJournalFeed.call(ctx.member_ctx, %{"sources" => "freeform"})

    assert only.id == personal.id

    assert {:ok, %{items: [found]}} =
             GetJournalFeed.call(ctx.member_ctx, %{"q" => "squat", "remember" => "true"})

    assert found.id == at_box.id
    assert {:ok, %{items: []}} = GetJournalFeed.call(ctx.member_ctx, %{"q" => "nothing like it"})

    assert {:ok, %{items: []}} =
             GetJournalFeed.call(ctx.member_ctx, %{"q" => "squat", "kinds" => "body"})

    assert {:ok, %{items: [_, _]}} =
             GetJournalFeed.call(ctx.member_ctx, %{
               "date_from" => Date.to_iso8601(Date.utc_today())
             })

    assert {:error, [q: _]} = GetJournalFeed.call(ctx.member_ctx, %{"q" => "x"})

    assert {:ok, %{last_used: %{"q" => "squat", "v" => 1}}} =
             Palee.Application.SavedFilters.get(ctx.member_ctx, "journal")
  end

  test "«Οι coach μου» names coaches: one coach of a gym can be left out", ctx do
    {:ok, personal} =
      JournalNotes.create(ctx.member_ctx, %{"topic" => "thought", "body" => "Tempo felt easy"})

    {:ok, _moved} =
      SetJournalVisibility.call(ctx.member_ctx, "note", personal.id, %{
        "visibility" => "coach_can_view"
      })

    for coach <- [ctx.box_owner, ctx.box_coach],
        do: assert(coach_sees(coach, ctx.box, ctx.member) == [personal.id])

    # Leave the box coach out: the box owner (who also coaches) still reads.
    owner = %{"organization_id" => ctx.box.id, "user_id" => ctx.box_owner.id}
    nikos = %{"organization_id" => ctx.nikos.id, "user_id" => ctx.nikos_owner.id}
    assert {:ok, %{coaches: [_, _]}} = JournalAudience.put_default(ctx.member_ctx, [owner, nikos])

    assert coach_sees(ctx.box_owner, ctx.box, ctx.member) == [personal.id]
    assert coach_sees(ctx.box_coach, ctx.box, ctx.member) == []
    assert coach_sees(ctx.nikos_owner, ctx.nikos, ctx.member) == [personal.id]

    # One entry for the box coach alone.
    box_coach = %{"organization_id" => ctx.box.id, "user_id" => ctx.box_coach.id}
    {:ok, _} = JournalAudience.put_entry(ctx.member_ctx, "note", personal.id, [box_coach])
    assert coach_sees(ctx.box_coach, ctx.box, ctx.member) == [personal.id]
    assert coach_sees(ctx.box_owner, ctx.box, ctx.member) == []
    assert coach_sees(ctx.nikos_owner, ctx.nikos, ctx.member) == []
    assert notes_visible_to(tenant!(ctx.box_owner, ctx.box), ctx.member) == []

    # A coach at the gym where it was recorded always reads it.
    {:ok, at_box} =
      JournalNotes.create(ctx.member_ctx, %{
        "topic" => "technique",
        "body" => "Box squat",
        "organization_slug" => ctx.box.slug
      })

    {:ok, _} =
      SetJournalVisibility.call(ctx.member_ctx, "note", at_box.id, %{
        "visibility" => "coach_can_view",
        "audience_coaches" => [nikos]
      })

    assert at_box.id in coach_sees(ctx.box_coach, ctx.box, ctx.member)
    assert at_box.id in coach_sees(ctx.nikos_owner, ctx.nikos, ctx.member)
  end

  test "leaving a provider ends its access from that day; the member keeps the history", ctx do
    {:ok, at_box} =
      JournalNotes.create(ctx.member_ctx, %{
        "topic" => "goal",
        "body" => "Sub 5 Fran",
        "organization_slug" => ctx.box.slug
      })

    {:ok, personal} = JournalNotes.create(ctx.member_ctx, %{"topic" => "mood", "body" => "Good"})

    for note <- [at_box, personal] do
      {:ok, _} =
        SetJournalVisibility.call(ctx.member_ctx, "note", note.id, %{
          "visibility" => "coach_can_view"
        })
    end

    assert length(coach_sees(ctx.box_coach, ctx.box, ctx.member)) == 2
    box_coach_ctx = tenant!(ctx.box_coach, ctx.box)
    execution!(ctx.box, ctx.member, fran!(ctx.box_owner, ctx.box), -1, 240)

    assert {:ok, %{total: 1}} =
             GetTrainingHistory.call(box_coach_ctx, ctx.member.id, %{"kind" => "workouts"})

    revoke!(ctx.box_owner, ctx.box, ctx.box_membership)

    # The coach read path refuses the former member outright...
    assert {:error, :not_found} = GetClientJournal.call(box_coach_ctx, ctx.member.id, %{})

    # ...and row security hides even the entries recorded there.
    assert notes_visible_to(box_coach_ctx, ctx.member) == []

    # The staff history read stops too (the box keeps its bookings).
    assert {:ok, %{total: 0, entries: []}} =
             GetTrainingHistory.call(box_coach_ctx, ctx.member.id, %{"kind" => "workouts"})

    # The member keeps everything, labelled «πρώην».
    assert {:ok, %{items: items}} = GetJournalFeed.call(ctx.member_ctx, %{})
    box_item = Enum.find(items, &(&1.id == at_box.id))

    assert box_item.source == %{
             kind: "organization",
             organization_id: ctx.box.id,
             name: "Box Kypseli",
             former: true
           }

    # Box ▾ moves the box to the former providers with its end date.
    assert {:ok, providers} = MyProviders.call(ctx.member_ctx)
    assert [%{organization_id: nikos_id, kind: "coach", selected: true}] = providers.providers
    assert nikos_id == ctx.nikos.id
    assert [%{organization_id: box_id, ended_at: %NaiveDateTime{}}] = providers.former
    assert box_id == ctx.box.id

    assert {:error, :unknown_provider} = MyProviders.select(ctx.member_ctx, ctx.box.id)

    # Rejoining restores the active membership and clears the end date.
    bypass_rls(fn ->
      {:ok, _} =
        Organizations.OrganizationStore.update_membership_status(
          ctx.box.id,
          ctx.box_membership.id,
          :active
        )
    end)

    assert {:ok, %{providers: [_, _], former: []}} = MyProviders.call(ctx.member_ctx)
  end

  test "a shared entry carries its comments to the other provider's coach", ctx do
    execution = execution!(ctx.box, ctx.member, fran!(ctx.box_owner, ctx.box), -1, 270)

    {:ok, _moved} =
      SetJournalVisibility.call(ctx.member_ctx, "execution", execution.id, %{
        "visibility" => "coach_can_view"
      })

    {:ok, comment} =
      JournalComments.save(ctx.member_ctx, Ecto.UUID.generate(), %{
        "entry_kind" => "execution",
        "entry_id" => execution.id,
        "body" => "Thrusters felt heavy"
      })

    nikos_ctx = tenant!(ctx.nikos_owner, ctx.nikos)
    assert comments_visible_to(tenant!(ctx.box_coach, ctx.box), execution) == [comment.id]
    assert comments_visible_to(nikos_ctx, execution) == []

    {:ok, _audience} =
      JournalAudience.put_entry(ctx.member_ctx, "execution", execution.id, [ctx.nikos.id])

    assert comments_visible_to(nikos_ctx, execution) == [comment.id]

    # Back to private: the comment leaves every coach with its entry.
    {:ok, _moved} =
      SetJournalVisibility.call(ctx.member_ctx, "execution", execution.id, %{
        "visibility" => "private"
      })

    assert comments_visible_to(nikos_ctx, execution) == []
  end

  test "Vault, Πρόοδος and history merge providers by workout identity", ctx do
    box_workout = fran!(ctx.box_owner, ctx.box)
    nikos_workout = fran!(ctx.nikos_owner, ctx.nikos)

    execution!(ctx.box, ctx.member, box_workout, -10, 300)
    execution!(ctx.nikos, ctx.member, nikos_workout, -3, 280)
    execution!(ctx.box, ctx.member, box_workout, -1, 260)

    assert {:ok, %{groups: [group]}} = GetAccountVault.call(ctx.member_ctx, %{})
    assert group.identity == "benchmark:fran"
    assert group.title == "Fran"
    assert group.attempt_count == 3
    assert Enum.map(group.sources, & &1.name) |> Enum.sort() == ["Box Kypseli", "Nikos PT"]

    assert {:ok, %{groups: [%{attempt_count: 1}]}} =
             GetAccountVault.call(ctx.member_ctx, %{"sources" => ctx.nikos.id})

    assert {:ok, %{groups: []}} = GetAccountVault.call(ctx.member_ctx, %{"benchmark" => "grace"})
    assert {:ok, %{groups: [_]}} = GetAccountVault.call(ctx.member_ctx, %{"exercise" => "thrust"})

    assert {:ok, progress} = GetAccountProgress.call(ctx.member_ctx, %{})
    assert progress.totals.sessions == 3
    assert [line] = progress.score_history
    assert line.workout_id == "benchmark:fran"
    assert length(line.points) == 3
    assert Enum.all?(line.points, &(&1.source.kind == "organization"))
    assert Enum.map(progress.by_source, & &1.sessions) == [2, 1]

    assert {:ok, %{totals: %{sessions: 1}}} =
             GetAccountProgress.call(ctx.member_ctx, %{"sources" => ctx.nikos.id})

    assert {:ok, %{totals: %{sessions: 1}}} =
             GetAccountProgress.call(ctx.member_ctx, %{"range" => "4w", "sources" => ctx.nikos.id})

    assert {:ok, %{totals: %{sessions: 0}}} =
             GetAccountProgress.call(ctx.member_ctx, %{"exercise" => "rowing"})

    assert {:ok, %{kind: "workouts", total: 3, entries: [first | _]}} =
             GetAccountHistory.call(ctx.member_ctx, %{"limit" => "2"})

    assert first.source.organization_id == ctx.box.id
    assert first.workout.title == "Fran"

    assert {:ok, %{total: 1}} =
             GetAccountHistory.call(ctx.member_ctx, %{"sources" => ctx.nikos.id})

    assert {:ok, %{kind: "classes", total: 0}} =
             GetAccountHistory.call(ctx.member_ctx, %{"kind" => "classes"})

    assert {:error, :invalid_history_kind} =
             GetAccountHistory.call(ctx.member_ctx, %{"kind" => "x"})
  end

  test "the export holds the whole journal across providers and notifies the member", ctx do
    box_workout = fran!(ctx.box_owner, ctx.box)
    execution!(ctx.box, ctx.member, box_workout, -1, 250)
    {:ok, _} = JournalNotes.create(ctx.member_ctx, %{"topic" => "mood", "body" => "Exported"})

    # Background jobs are off in tests: the request builds it inline.
    assert {:ok, %{status: "ready", entry_count: 2, files: [json, csv]}} =
             JournalExports.request(ctx.member_ctx)

    assert json.name == "journal.json"
    assert csv.name == "training.csv"
    assert is_binary(json.download_url)

    assert {:ok, [%{status: "ready"}]} = JournalExports.list(ctx.member_ctx)

    assert {:ok, [%{status: "expired", files: []}]} =
             JournalExports.list(ctx.member_ctx, DateTime.add(DateTime.utc_now(), 8, :day))

    assert bypass_rls(fn ->
             Repo.aggregate(
               from(n in Notification,
                 where: n.user_id == ^ctx.member.id and n.type == :journal_export_ready
               ),
               :count
             )
           end) == 1

    # Another person sees none of it.
    other = UserContext.new(user_fixture())
    assert {:ok, []} = JournalExports.list(other)
  end

  test "the export job builds a pending export once, in the member's session", ctx do
    {:ok, export} =
      Palee.Journal.with_context(ctx.member_ctx, fn ->
        Palee.Journal.insert_export(%{
          user_id: ctx.member.id,
          requested_at: DateTime.utc_now()
        })
      end)

    job = fn id ->
      Palee.Workers.JournalExportJob.perform(%Oban.Job{
        args: %{"user_id" => ctx.member.id, "export_id" => id},
        attempt: 1,
        max_attempts: 3
      })
    end

    assert job.(export.id) == :ok
    assert {:ok, [%{status: "ready", entry_count: 0}]} = JournalExports.list(ctx.member_ctx)
    # Built once: a retried job leaves it as it is.
    assert job.(export.id) == :ok
    assert job.(Ecto.UUID.generate()) == :ok

    # Someone else's job cannot reach the member's export.
    other = user_fixture()

    assert Palee.Workers.JournalExportJob.perform(%Oban.Job{
             args: %{"user_id" => other.id, "export_id" => export.id},
             attempt: 1,
             max_attempts: 3
           }) == :ok

    # A failure reported after it was built changes nothing.
    assert {:ok, :skipped} = JournalExports.fail(ctx.member_ctx, export.id, :late)
    assert {:ok, [%{status: "ready"}]} = JournalExports.list(ctx.member_ctx)
  end

  # ---------------------------------------------------------------- helpers

  defp coach_sees(coach, organization, member) do
    {:ok, %{items: items}} = GetClientJournal.call(tenant!(coach, organization), member.id, %{})
    Enum.map(items, & &1.id)
  end

  defp notes_visible_to(context, member) do
    Palee.Journal.with_context(context, fn ->
      Repo.all(
        from(n in "journal_notes", where: n.user_id == type(^member.id, :binary_id), select: n.id)
      )
    end)
  end

  defp comments_visible_to(context, entry) do
    Palee.Journal.with_context(context, fn ->
      Repo.all(
        from(c in "journal_comments",
          where: c.entry_id == type(^entry.id, :binary_id),
          select: type(c.id, :binary_id)
        )
      )
    end)
  end

  defp org!(name, kind) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    Repo.query!("UPDATE organizations SET provider_kind = $1, name = $2 WHERE id = $3", [
      kind,
      name,
      Ecto.UUID.dump!(organization.id)
    ])

    %{organization | name: name}
  end

  # An owner here also coaches: an independent coach is a one-person organization.
  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        roles: if(role == :owner, do: [:owner, :coach], else: [role]),
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp revoke!(owner, organization, membership) do
    {:ok, _} =
      Organizations.set_membership_status(tenant!(owner, organization), membership.id, "revoked")
  end

  defp tenant!(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end

  defp fran!(owner, organization) do
    workout_fixture(owner, %{
      tenant_context: tenant!(owner, organization),
      title: "Fran",
      sections: [
        %{
          name: "21-15-9",
          order: 1,
          scoreable: true,
          score_config: %{type: "time"},
          exercises: [
            %{
              name: "Thruster",
              order: 1,
              sets: 1,
              prescription_value: 45,
              prescription_unit: "reps"
            }
          ]
        }
      ]
    })
  end

  defp execution!(organization, member, workout, days, seconds) do
    at = DateTime.add(DateTime.utc_now(), days, :day)
    section = hd(workout.sections)

    bypass_rls(fn ->
      %WorkoutExecution{organization_id: organization.id}
      |> WorkoutExecution.start_changeset(%{
        user_id: member.id,
        master_workout_id: workout.id,
        source: :self_selected,
        status: :completed,
        started_at_utc: at,
        started_at_tz: "UTC"
      })
      |> Ecto.Changeset.put_change(:completed_at_utc, at)
      |> Ecto.Changeset.put_change(:completed_at_tz, "UTC")
      |> Ecto.Changeset.put_change(:total_elapsed_ms, seconds * 1000)
      |> Ecto.Changeset.put_change(:section_scores, [
        %{"section_id" => section.id, "value" => seconds, "unit" => "s"}
      ])
      |> Repo.insert!()
    end)
  end
end
