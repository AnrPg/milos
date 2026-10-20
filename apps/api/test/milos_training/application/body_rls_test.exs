defmodule MilosTraining.Application.BodyRLSTest do
  @moduledoc """
  ADR-158 at the database level, under the RLS-enforcing runtime role and
  without the application's own filters: a coach session reads only shared
  snapshots of an active member of that gym, photos only on `coach_full`
  with an active consent, and nothing of a member of another gym; the
  member reads their access log, no one else's.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.{Body, Media, Organizations}
  alias MilosTraining.Identity.UserContext

  setup do
    fixtures =
      bypass_rls(fn ->
        {:ok, gym} = Organizations.create_organization(%{name: "Body Gym"})
        {:ok, other_gym} = Organizations.create_organization(%{name: "Other Body Gym"})
        coach = user_fixture()
        member = user_fixture()
        stranger = user_fixture()
        add!(gym, coach, :coach)
        add!(gym, member, :member)
        add!(other_gym, coach, :coach)
        add!(other_gym, stranger, :member)
        %{gym: gym, other_gym: other_gym, coach: coach, member: member, stranger: stranger}
      end)

    Map.merge(fixtures, %{
      member_ctx: UserContext.new(fixtures.member),
      coach_ctx: tenant!(fixtures.coach, fixtures.gym),
      other_coach_ctx: tenant!(fixtures.coach, fixtures.other_gym)
    })
  end

  defp snapshot!(ctx, visibility, metrics \\ %{"waist" => 80.0}) do
    {:ok, snapshot} =
      Body.create_snapshot(ctx.member_ctx, %{
        user_id: ctx.member.id,
        taken_at: DateTime.utc_now(),
        metrics: metrics,
        visibility: visibility
      })

    snapshot
  end

  defp photo!(ctx, snapshot) do
    id = Ecto.UUID.generate()

    {:ok, _media} =
      Media.create(ctx.member_ctx, :account, %{
        id: id,
        purpose: "body_photo",
        object_key: "users/#{ctx.member.id}/media/body/#{id}/original.jpg",
        content_type: "image/jpeg"
      })

    {:ok, photo} =
      Body.insert_photo(ctx.member_ctx, %{
        user_id: ctx.member.id,
        snapshot_id: snapshot.id,
        media_id: id,
        pose: "front",
        status: "ready",
        variants: %{"full" => %{"key" => "users/#{ctx.member.id}/media/body/#{id}/full.webp"}}
      })

    photo
  end

  test "a coach session sees shared snapshots only, photos only with consent", ctx do
    private = snapshot!(ctx, "private")
    numbers = snapshot!(ctx, "coach_numbers")
    full = snapshot!(ctx, "coach_full")
    for snapshot <- [private, numbers, full], do: photo!(ctx, snapshot)

    # Without the application's shared_only filter.
    seen = Body.list_snapshots(ctx.coach_ctx, ctx.member.id, limit: 10)
    assert seen |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([numbers.id, full.id])
    assert Body.get_snapshot(ctx.coach_ctx, ctx.member.id, private.id) == nil

    ids = [private.id, numbers.id, full.id]
    assert Body.list_photos(ctx.coach_ctx, ids) == []
    refute Body.photos_consented?(ctx.coach_ctx, ctx.member.id)

    {:ok, _consent} =
      Body.grant_consent(ctx.member_ctx, ctx.member.id, "body_photos", DateTime.utc_now())

    assert [%{snapshot_id: snapshot_id}] = Body.list_photos(ctx.coach_ctx, ids)
    assert snapshot_id == full.id

    1 = Body.withdraw_consent(ctx.member_ctx, ctx.member.id, "body_photos", DateTime.utc_now())
    assert Body.list_photos(ctx.coach_ctx, ids) == []

    # The owner sees everything of their own.
    assert length(Body.list_snapshots(ctx.member_ctx, ctx.member.id, limit: 10)) == 3
    assert length(Body.list_photos(ctx.member_ctx, ids)) == 3

    # A coach session can read a shared snapshot but never write it.
    assert_raise Ecto.StaleEntryError, fn ->
      Body.update_snapshot(ctx.coach_ctx, ctx.member.id, numbers.id, %{notes: "x"})
    end
  end

  test "a coach of another gym, or of a member who left, sees nothing", ctx do
    shared = snapshot!(ctx, "coach_full")

    assert Body.list_snapshots(ctx.other_coach_ctx, ctx.member.id, limit: 10) == []
    assert Body.get_snapshot(ctx.other_coach_ctx, ctx.member.id, shared.id) == nil

    bypass_rls(fn ->
      MilosTraining.Repo.query!(
        "UPDATE organization_memberships SET status = 'suspended' WHERE user_id = $1",
        [Ecto.UUID.dump!(ctx.member.id)]
      )
    end)

    assert Body.list_snapshots(ctx.coach_ctx, ctx.member.id, limit: 10) == []
  end

  test "settings: the coach reads the display choice, a stranger nothing", ctx do
    {:ok, _settings} =
      Body.put_settings(ctx.member_ctx, ctx.member.id, %{weight_display: "hidden"})

    assert %{weight_display: "hidden"} = Body.settings(ctx.coach_ctx, ctx.member.id)
    # Defaults stand in when nothing is readable.
    assert %{weight_display: "number"} = Body.settings(ctx.other_coach_ctx, ctx.member.id)

    assert %{weight_display: "number"} =
             Body.settings(UserContext.new(ctx.stranger), ctx.member.id)
  end

  test "the access log: written in the coach's gym, read by the member", ctx do
    shared = snapshot!(ctx, "coach_numbers")

    :ok =
      Body.record_access(ctx.coach_ctx, %{
        organization_id: ctx.gym.id,
        user_id: ctx.member.id,
        reader_user_id: ctx.coach.id,
        subject: "list",
        snapshot_ids: [shared.id],
        photos_shown: false
      })

    assert [%{reader_user_id: reader}] = Body.list_access_log(ctx.member_ctx, ctx.member.id, 10)
    assert reader == ctx.coach.id
    assert Body.list_access_log(UserContext.new(ctx.stranger), ctx.member.id, 10) == []
    assert Body.list_access_log(ctx.other_coach_ctx, ctx.member.id, 10) == []
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
