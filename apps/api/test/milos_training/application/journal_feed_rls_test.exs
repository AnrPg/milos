defmodule MilosTraining.Application.JournalFeedRLSTest do
  @moduledoc """
  ADR-139 read side under real Row Level Security: the member's feed merges
  every kind newest first and pages by cursor; entries move on the ladder
  (a personal one only to private); Ζητάω απάντηση needs a coach and sends
  the question as a message about the entry; a coach reads only what reaches
  them, and each read is audited.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{
    CreatePR,
    GetClientJournal,
    GetJournalFeed,
    JournalNotes,
    SetJournalVisibility
  }

  alias MilosTraining.{Coaching, Organizations, Repo}
  alias MilosTraining.Identity.UserContext

  setup do
    fixtures =
      bypass_rls(fn ->
        {:ok, gym} = Organizations.create_organization(%{name: "Journal Gym"})
        coach = user_fixture()
        member = user_fixture()
        add!(gym, coach, :coach)
        add!(gym, member, :member)
        %{gym: gym, coach: coach, member: member}
      end)

    Map.merge(fixtures, %{
      member_ctx: UserContext.new(fixtures.member),
      coach_ctx: tenant!(fixtures.coach, fixtures.gym)
    })
  end

  test "the feed merges kinds newest first and pages by cursor", ctx do
    {:ok, older} =
      JournalNotes.create(
        ctx.member_ctx,
        %{"topic" => "thought", "body" => "Older"},
        ~U[2026-10-01 08:00:00.000000Z]
      )

    {:ok, pr} = CreatePR.call(ctx.member_ctx, pr_params(ctx.gym, "2026-10-02"))

    {:ok, newer} =
      JournalNotes.create(
        ctx.member_ctx,
        %{"topic" => "goal", "body" => "Newer", "organization_slug" => ctx.gym.slug},
        ~U[2026-10-03 08:00:00.000000Z]
      )

    assert {:ok, %{items: [first, second], next_cursor: cursor}} =
             GetJournalFeed.call(ctx.member_ctx, %{"limit" => 2})

    assert {first.kind, first.id} == {"note", newer.id}
    assert {second.kind, second.id} == {"pr", pr.id}
    assert second.occurred_on == ~D[2026-10-02]
    assert first.choosable_visibilities == ~w(private coach_can_view coach_reply_requested)
    assert is_binary(cursor)

    assert {:ok, %{items: [last], next_cursor: nil}} =
             GetJournalFeed.call(ctx.member_ctx, %{"limit" => 2, "cursor" => cursor})

    assert last.id == older.id
    # ADR-162: a personal note can go to the member's coaches (every active
    # provider by default), but a reply request needs the entry's own gym.
    assert last.choosable_visibilities == ["private", "coach_can_view"]
    assert last.source == %{kind: "freeform", organization_id: nil, name: nil, former: false}
    assert last.audience == %{custom: false, organization_ids: [ctx.gym.id]}

    assert {:ok, %{items: [%{kind: "pr"}]}} =
             GetJournalFeed.call(ctx.member_ctx, %{"kinds" => "pr,execution"})

    assert {:error, :invalid_cursor} = GetJournalFeed.call(ctx.member_ctx, %{"cursor" => "x"})
    assert {:error, :unknown_kind} = GetJournalFeed.call(ctx.member_ctx, %{"kinds" => "post"})
  end

  test "entries move on the ladder; a personal one only to private", ctx do
    {:ok, gym_note} =
      JournalNotes.create(ctx.member_ctx, %{
        "topic" => "technique",
        "body" => "Elbows up",
        "organization_slug" => ctx.gym.slug
      })

    {:ok, personal} = JournalNotes.create(ctx.member_ctx, %{"topic" => "mood", "body" => "Tired"})

    assert gym_note.journal_visibility == "private"

    assert {:ok, %{journal_visibility: "coach_can_view", reply_request: nil}} =
             SetJournalVisibility.call(ctx.member_ctx, "note", gym_note.id, %{
               "visibility" => "coach_can_view"
             })

    assert {:error, :no_gym_for_entry} =
             SetJournalVisibility.call(ctx.member_ctx, "note", personal.id, %{
               "visibility" => "coach_reply_requested",
               "question" => "Why?"
             })

    assert {:ok, %{journal_visibility: "coach_can_view"}} =
             SetJournalVisibility.call(ctx.member_ctx, "note", personal.id, %{
               "visibility" => "coach_can_view"
             })

    assert {:error, :visibility_not_allowed} =
             SetJournalVisibility.call(ctx.member_ctx, "note", gym_note.id, %{
               "visibility" => "posted"
             })

    assert {:error, :not_found} =
             SetJournalVisibility.call(ctx.member_ctx, "note", Ecto.UUID.generate(), %{
               "visibility" => "private"
             })
  end

  test "Ζητάω απάντηση needs a coach and sends the question about the entry", ctx do
    {:ok, note} =
      JournalNotes.create(ctx.member_ctx, %{
        "topic" => "technique",
        "body" => "Knees cave",
        "organization_slug" => ctx.gym.slug
      })

    ask = %{"visibility" => "coach_reply_requested", "question" => "  How do I fix this?  "}

    assert {:error, :no_active_coach} =
             SetJournalVisibility.call(ctx.member_ctx, "note", note.id, ask)

    # Nothing moved: the move and the message happen together.
    assert {:ok, %{items: [%{journal_visibility: "private"}]}} =
             GetJournalFeed.call(ctx.member_ctx, %{})

    bypass_rls(fn ->
      {:ok, _relationship} =
        Coaching.start_relationship(%{organization_id: ctx.gym.id}, %{
          coach_user_id: ctx.coach.id,
          client_user_id: ctx.member.id,
          origin: "assigned"
        })
    end)

    assert {:error, :question_required} =
             SetJournalVisibility.call(ctx.member_ctx, "note", note.id, %{
               "visibility" => "coach_reply_requested"
             })

    assert {:ok, %{journal_visibility: "coach_reply_requested", reply_request: %{id: message_id}}} =
             SetJournalVisibility.call(ctx.member_ctx, "note", note.id, ask)

    message =
      bypass_rls(fn -> Repo.get!(MilosTraining.Messaging.Message, message_id) end)

    assert message.body == "How do I fix this?"
    assert {message.subject_kind, message.subject_id} == {"note", note.id}
    assert message.sender_id == ctx.member.id
  end

  test "a coach reads only what reaches them, and every read is audited", ctx do
    {:ok, shown} = CreatePR.call(ctx.member_ctx, pr_params(ctx.gym, "2026-10-02"))

    {:ok, hidden} =
      JournalNotes.create(ctx.member_ctx, %{
        "topic" => "thought",
        "body" => "Just for me",
        "organization_slug" => ctx.gym.slug
      })

    {:ok, _personal} = JournalNotes.create(ctx.member_ctx, %{"topic" => "goal", "body" => "Mine"})

    assert {:ok, %{items: items}} = GetClientJournal.call(ctx.coach_ctx, ctx.member.id, %{})
    assert Enum.map(items, &{&1.kind, &1.id}) == [{"pr", shown.id}]
    refute Enum.any?(items, &(&1.id == hidden.id))

    reads =
      bypass_rls(fn ->
        Repo.all(
          from(read in "journal_coach_reads",
            select:
              {read.entry_kind, type(read.entry_id, :binary_id),
               type(read.reader_user_id, :binary_id)}
          )
        )
      end)

    assert reads == [{"pr", shown.id, ctx.coach.id}]

    member_ctx = tenant!(ctx.member, ctx.gym)
    assert {:error, :forbidden} = GetClientJournal.call(member_ctx, ctx.member.id, %{})
    assert {:error, :not_found} = GetClientJournal.call(ctx.coach_ctx, Ecto.UUID.generate(), %{})
  end

  defp pr_params(gym, beaten_on) do
    %{
      "name" => "Back squat",
      "current_score" => 100,
      "unit" => "kg",
      "higher_is_better" => true,
      "beaten_on" => beaten_on,
      "supporting_metrics" => %{"reps" => 1},
      "organization_slug" => gym.slug
    }
  end

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp tenant!(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end
end
