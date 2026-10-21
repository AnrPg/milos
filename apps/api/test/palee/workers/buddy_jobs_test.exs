defmodule Palee.Workers.BuddyJobsTest do
  @moduledoc """
  ADR-160 jobs: the timed steps of a support request (deliver after the
  undo window, the no-reply card) and the Sunday 19:00 weekly summary in
  the member's zone; and the port M11's Λιγούρα calls.
  """

  use Palee.DataCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.{Buddies, SupportRequests}
  alias Palee.Buddies, as: BuddyContext
  alias Palee.Notifications.Notification
  alias Palee.{Organizations, Repo}
  alias Palee.Workers.{BuddyWeeklySummaryJob, SupportRequestJob}

  setup do
    {:ok, gym} = Organizations.create_organization(%{name: "Jobs Buddy Box"})
    member = user_fixture()
    buddy = user_fixture()

    for user <- [member, buddy] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: gym.id,
          user_id: user.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    member_ctx = %{user_id: member.id, account: member}
    buddy_ctx = %{user_id: buddy.id, account: buddy}
    {:ok, link} = Buddies.invite(member_ctx, %{"user_id" => buddy.id})
    {:ok, _} = Buddies.accept(buddy_ctx, link.id)

    %{member: member, buddy: buddy, member_ctx: member_ctx, link: link}
  end

  defp notifications(user, type),
    do: Repo.all(from(n in Notification, where: n.user_id == ^user.id and n.type == ^type))

  defp job(args), do: %Oban.Job{args: args}

  test "deliver and nudge steps are idempotent", ctx do
    {:ok, request} = SupportRequests.create(ctx.member_ctx, %{"message" => "hard evening"})
    args = %{"user_id" => ctx.member.id, "request_id" => request.id}

    assert :ok = SupportRequestJob.perform(job(Map.put(args, "step", "deliver")))
    assert :ok = SupportRequestJob.perform(job(Map.put(args, "step", "deliver")))
    assert [_once] = notifications(ctx.buddy, :support_request)

    # The job runs at ten minutes; before that nothing is sent.
    assert :ok = SupportRequestJob.perform(job(Map.put(args, "step", "nudge")))
    assert notifications(ctx.member, :support_no_reply_nudge) == []

    assert :ok =
             SupportRequests.nudge(
               ctx.member.id,
               request.id,
               DateTime.add(DateTime.utc_now(), 601, :second)
             )

    assert [_card] = notifications(ctx.member, :support_no_reply_nudge)

    assert {:cancel, :unknown_step} = SupportRequestJob.perform(job(Map.put(args, "step", "x")))

    assert :ok =
             SupportRequestJob.perform(
               job(%{
                 "user_id" => ctx.member.id,
                 "request_id" => Ecto.UUID.generate(),
                 "step" => "deliver"
               })
             )
  end

  test "M11's port: source craving, only an opaque reference, nothing about the craving", ctx do
    craving_id = Ecto.UUID.generate()

    assert :ok =
             SupportRequests.request(%{user_id: ctx.member.id}, %{
               user_id: ctx.member.id,
               craving_id: craving_id,
               at: DateTime.utc_now()
             })

    assert {:ok, [%{source: "craving", message: nil} = request]} =
             SupportRequests.list(ctx.member_ctx, %{})

    assert %{source_ref: ^craving_id} = BuddyContext.get_request(ctx.member_ctx, request.id)

    :ok = SupportRequests.deliver(ctx.member.id, request.id)
    assert [%{payload: payload}] = notifications(ctx.buddy, :support_request)
    refute inspect(payload) =~ craving_id
    refute Map.has_key?(payload, "source")

    # Without a buddy (or over the hourly limit) the craving is still saved.
    stranger = user_fixture()

    assert :ok =
             SupportRequests.request(%{}, %{
               user_id: stranger.id,
               craving_id: Ecto.UUID.generate(),
               at: DateTime.utc_now()
             })
  end

  test "the weekly summary job sends on Sunday 19:00 in the member's zone", ctx do
    {:ok, _} =
      Buddies.update_link(ctx.member_ctx, ctx.link.id, %{"receives_weekly_summary" => true})

    # Saturday evening: not yet.
    assert :ok = Palee.Application.BuddyWeeklySummaries.call(~U[2026-10-24 16:00:00Z])
    assert notifications(ctx.buddy, :buddy_weekly_summary) == []

    # Sunday 19:00 in Athens (UTC+2 after the clocks change).
    assert :ok = Palee.Application.BuddyWeeklySummaries.call(~U[2026-10-25 17:00:00Z])
    assert :ok = Palee.Application.BuddyWeeklySummaries.call(~U[2026-10-25 17:30:00Z])

    assert [%{payload: %{"week_start" => "2026-10-19", "hard_moments" => 0}}] =
             notifications(ctx.buddy, :buddy_weekly_summary)

    assert :ok = BuddyWeeklySummaryJob.perform(%Oban.Job{args: %{}})
  end
end
