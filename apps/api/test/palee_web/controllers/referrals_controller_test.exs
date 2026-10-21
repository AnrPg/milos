defmodule Palee.Web.ReferralsControllerTest do
  @moduledoc """
  ADR-156 (P2-M8, board 11): a member's invite, from the link to the reward,
  through the endpoints and the domain events that move it.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{DomainEvents, Finance, Notifications, Organizations, Repo}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.Referrals.ReferralAttribution

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Referral Gym #{System.unique_integer([:positive])}"
      })

    person = fn role ->
      user = user_fixture()

      if role do
        {:ok, _membership} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      user
    end

    owner = person.(:owner)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(owner_context, %{
        "about" => "Φέρε φίλους.",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(owner_context, %{"lock_version" => profile.lock_version})

    %{
      organization: organization,
      slug: organization.slug,
      owner: owner,
      owner_context: owner_context,
      member: person.(:member),
      other_member: person.(:member),
      coach: person.(:coach),
      friend: person.(nil),
      as: fn user -> put_bearer_token(conn, user) end,
      admin: "/api/org/#{organization.slug}/admin",
      me: "/api/org/#{organization.slug}/me"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp drain, do: Oban.drain_queue(queue: :notifications, with_safety: false)

  defp notices(user, type) do
    user.id
    |> Notifications.list_for_user()
    |> Enum.filter(&(to_string(&1.type) == type))
  end

  defp program!(ctx, attrs \\ %{}) do
    ctx.as.(ctx.owner)
    |> send_json(
      :post,
      "#{ctx.admin}/finance/referral-programs",
      Map.merge(
        %{
          name: "Οκτώβριος",
          active: true,
          reward_type: "credit",
          reward_value: 2_000,
          friend_reward_type: "free_days",
          friend_reward_value: 7,
          attribution_days: 60,
          approval: "manual"
        },
        attrs
      )
    )
    |> json_response(201)
    |> Map.fetch!("referral_program")
  end

  defp overview(ctx, user), do: ctx.as.(user) |> get("#{ctx.me}/referrals") |> json_response(200)

  defp claim(ctx, user, code, extra \\ %{}) do
    ctx.as.(user)
    |> send_json(:post, "/api/referrals/claim", Map.merge(%{code: code}, extra))
  end

  defp attribution(ctx, user),
    do:
      Repo.get_by!(ReferralAttribution,
        organization_id: ctx.organization.id,
        referred_user_id: user.id
      )

  # The friend's first package and its payment, recorded by the owner.
  defp first_payment!(ctx, user) do
    {:ok, package} =
      Finance.create_package(ctx.owner_context, %{
        name: "Μηνιαίο #{System.unique_integer([:positive])}",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, membership} =
      Finance.upsert_membership(ctx.owner_context, user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, subscription} =
      Finance.assign_package(ctx.owner_context, membership.id, package.id, %{
        ends_on: Date.add(Date.utc_today(), 30)
      })

    ctx.as.(ctx.owner)
    |> send_json(:post, "#{ctx.admin}/finance/members/#{user.id}/receipts", %{
      amount_cents: 6_000,
      payment_method: "cash",
      paid_on: Date.to_iso8601(Date.utc_today()),
      description: "Πρώτος μήνας",
      membership_package_subscription_id: subscription.id,
      idempotency_key: Ecto.UUID.generate()
    })
    |> json_response(201)

    {membership, subscription}
  end

  defp finance_record!(ctx, user) do
    {:ok, membership} =
      Finance.upsert_membership(ctx.owner_context, user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    membership
  end

  defp credit_cents(membership_id) do
    import Ecto.Query

    Repo.one(
      from(e in Palee.Finance.FinanceCreditLedgerEntry,
        where: e.membership_id == ^membership_id,
        select: coalesce(sum(e.amount_cents), 0)
      )
    )
  end

  defp join!(ctx, user) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: ctx.organization.id,
        user_id: user.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    DomainEvents.publish(:membership_activated, %{
      organization_id: ctx.organization.id,
      user_id: user.id,
      at: DateTime.utc_now()
    })
  end

  describe "the member's «Φέρε φίλο»" do
    test "makes one code, shows the programme and the box's open events", ctx do
      program = program!(ctx, %{friend_reward_note: nil, yearly_cap: 5})

      first = overview(ctx, ctx.member)
      assert %{"code" => code, "path" => path, "earns_rewards" => true} = first
      assert path == "/r/" <> code
      assert String.length(code) == 8
      assert overview(ctx, ctx.member)["code"] == code

      assert %{
               "id" => program_id,
               "reward" => %{"type" => "credit", "value" => 2_000},
               "gift" => %{"type" => "free_days", "value" => 7},
               "qualifying_stage" => "paid",
               "attribution_days" => 60,
               "yearly_cap" => 5
             } = first["program"]

      assert program_id == program["id"]
      assert first["invites"] == []
      assert first["totals"] == %{"invited" => 0, "trials" => 0, "paid" => 0}

      # Staff share the link but don't earn (board 11 Q4).
      assert %{"earns_rewards" => false} = overview(ctx, ctx.coach)
    end

    test "events staff tag «Καλό για φίλους» come first, open ones only", ctx do
      club_id =
        ctx.as.(ctx.member)
        |> get("/api/me/clubs")
        |> json_response(200)
        |> Map.fetch!("clubs")
        |> Enum.find(&(&1["kind"] == "gym"))
        |> Map.fetch!("id")

      staff_events = "#{ctx.admin}/community/events"

      event = fn title, days, attrs ->
        starts_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(days, :day)

        ctx.as.(ctx.coach)
        |> send_json(
          :post,
          staff_events,
          Map.merge(
            %{
              club_id: club_id,
              title: title,
              starts_at: DateTime.to_iso8601(starts_at),
              ends_at: starts_at |> DateTime.add(1, :hour) |> DateTime.to_iso8601(),
              place_name: "Box",
              open_to_non_members: true
            },
            attrs
          )
        )
      end

      soon = event.("Open WOD", 2, %{}) |> json_response(201)
      later = event.("Bring a friend WOD", 9, %{good_for_friends: true}) |> json_response(201)
      assert later["event"]["good_for_friends"]
      refute soon["event"]["good_for_friends"]

      # A members-only event can't take the tag.
      assert %{"errors" => %{"good_for_friends" => [_]}} =
               event.("Members only", 3, %{open_to_non_members: false, good_for_friends: true})
               |> json_response(422)

      assert [
               %{"title" => "Bring a friend WOD", "good_for_friends" => true},
               %{"title" => "Open WOD", "good_for_friends" => false}
             ] =
               overview(ctx, ctx.member)["events"]
               |> Enum.map(&Map.take(&1, ~w(title good_for_friends)))
    end

    test "a new code retires the old link", ctx do
      %{"code" => old} = overview(ctx, ctx.member)

      assert %{"code" => new} =
               ctx.as.(ctx.member)
               |> send_json(:post, "#{ctx.me}/referrals/code", %{})
               |> json_response(200)

      assert new != old
      assert ctx.conn |> get("/api/public/referrals/#{old}") |> json_response(404)
      assert ctx.conn |> get("/api/public/referrals/#{new}") |> json_response(200)
    end

    test "activating a programme retires the one before", ctx do
      first = program!(ctx)
      second = program!(ctx, %{name: "Νοέμβριος", reward_value: 3_000})

      programs =
        ctx.as.(ctx.owner)
        |> get("#{ctx.admin}/finance/referral-programs")
        |> json_response(200)
        |> Map.fetch!("referral_programs")
        |> Map.new(&{&1["id"], &1["active"]})

      assert programs[first["id"]] == false
      assert programs[second["id"]] == true
      assert overview(ctx, ctx.member)["program"]["id"] == second["id"]
    end
  end

  describe "the invite page and the claim" do
    test "anyone sees who invites to which box and the friend's gift", ctx do
      program!(ctx)
      %{"code" => code} = overview(ctx, ctx.member)

      assert %{
               "invite" => %{
                 "code" => ^code,
                 "box" => %{"slug" => slug, "published" => true, "disciplines" => ["crossfit"]},
                 "inviter" => %{"nickname" => nickname},
                 "gift" => %{"type" => "free_days", "value" => 7},
                 "trials_enabled" => false
               }
             } =
               ctx.conn
               |> get("/api/public/referrals/#{String.downcase(code)}")
               |> json_response(200)

      assert slug == ctx.slug
      assert nickname == ctx.member.nickname
      assert ctx.conn |> get("/api/public/referrals/ZZZZZZZZ") |> json_response(404)
    end

    test "the link used owns the invite; members and self-invites are never counted", ctx do
      program!(ctx)
      %{"code" => code} = overview(ctx, ctx.member)
      %{"code" => other_code} = overview(ctx, ctx.other_member)

      assert %{"outcome" => "claimed", "box" => %{"slug" => slug}} =
               claim(ctx, ctx.friend, code, %{new_account: true}) |> json_response(200)

      assert slug == ctx.slug
      assert %{"outcome" => "unchanged"} = claim(ctx, ctx.friend, code) |> json_response(200)

      assert %{"outcome" => "self"} = claim(ctx, ctx.member, code) |> json_response(200)

      assert %{"outcome" => "already_member"} =
               claim(ctx, ctx.other_member, code) |> json_response(200)

      invite = attribution(ctx, ctx.friend)
      assert invite.referrer_user_id == ctx.member.id
      assert invite.new_account
      assert invite.channel == "link"
      assert DateTime.diff(invite.expires_at, invite.attributed_at, :day) == 60

      drain()
      assert [_signed_up] = notices(ctx.member, "referral_progress")

      assert %{"invites" => [%{"stage" => "signed_up", "reward" => %{"status" => "upcoming"}}]} =
               overview(ctx, ctx.member)

      # The friend uses another member's personal link: the invite is theirs now.
      assert %{"outcome" => "claimed"} = claim(ctx, ctx.friend, other_code) |> json_response(200)
      moved = attribution(ctx, ctx.friend)
      assert moved.referrer_user_id == ctx.other_member.id
      assert moved.previous_referrer_user_id == ctx.member.id
      assert overview(ctx, ctx.member)["invites"] == []
      assert [_moved] = overview(ctx, ctx.other_member)["invites"]

      # Once it counted, another link changes nothing.
      first_payment!(ctx, ctx.friend)

      assert %{"outcome" => "already_invited"} =
               claim(ctx, ctx.friend, code) |> json_response(200)

      assert attribution(ctx, ctx.friend).referrer_user_id == ctx.other_member.id
    end

    test "an invite that ran out leaves room for another member's", ctx do
      program!(ctx)
      %{"code" => code} = overview(ctx, ctx.member)
      %{"code" => other_code} = overview(ctx, ctx.other_member)
      assert %{"outcome" => "claimed"} = claim(ctx, ctx.friend, code) |> json_response(200)

      past = DateTime.add(DateTime.utc_now(), -1, :day)

      ctx
      |> attribution(ctx.friend)
      |> Ecto.Changeset.change(attributed_at: DateTime.add(past, -60, :day), expires_at: past)
      |> Repo.update!()

      assert %{"outcome" => "claimed"} = claim(ctx, ctx.friend, other_code) |> json_response(200)
      assert attribution(ctx, ctx.friend).referrer_user_id == ctx.other_member.id
    end
  end

  describe "the funnel and the reward" do
    test "event, trial, joining and the first payment; the owner approves; the credit lands",
         ctx do
      program!(ctx)
      referrer_membership = finance_record!(ctx, ctx.member)
      %{"code" => code} = overview(ctx, ctx.member)
      claim(ctx, ctx.friend, code, %{channel: "qr"}) |> json_response(200)

      DomainEvents.publish(:event_attendance_recorded, %{
        organization_id: ctx.organization.id,
        community_event_id: Ecto.UUID.generate(),
        user_id: ctx.friend.id,
        at: DateTime.utc_now()
      })

      DomainEvents.publish(:attendance_recorded, %{
        organization_id: ctx.organization.id,
        scheduled_class_id: Ecto.UUID.generate(),
        user_id: ctx.friend.id,
        booking_id: nil,
        status: "attended",
        at: DateTime.utc_now()
      })

      join!(ctx, ctx.friend)
      assert %{"invites" => [%{"stage" => "joined"}]} = overview(ctx, ctx.member)

      {_membership, _subscription} = first_payment!(ctx, ctx.friend)

      invite = attribution(ctx, ctx.friend)
      assert invite.status == "qualified"
      assert invite.event_at && invite.trial_at && invite.joined_at && invite.paid_at
      assert invite.finance_referral_event_id

      # The friend's Finance record says who brought them.
      assert %{membership: %{referred_by_user_id: referrer, signup_source: "referral"}} =
               Finance.get_member_profile(ctx.owner_context, ctx.friend.id)

      assert referrer == ctx.member.id

      assert %{"invites" => [%{"stage" => "paid", "reward" => %{"status" => "pending"}}]} =
               overview(ctx, ctx.member)

      drain()
      assert [_review] = notices(ctx.owner, "referral_review")
      stages = ctx.member |> notices("referral_progress") |> Enum.map(& &1.payload["stage"])
      assert Enum.sort(stages) == ~w(event paid signed_up trial)

      assert %{"invites" => [%{"id" => id, "referrer" => %{"id" => referrer_id}}]} =
               ctx.as.(ctx.owner)
               |> get("#{ctx.admin}/referrals?filter=review")
               |> json_response(200)

      assert referrer_id == ctx.member.id

      assert %{"invite" => %{"reward" => %{"status" => "given"}}} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/referrals/#{id}/approve", %{})
               |> json_response(200)

      assert %{"invites" => []} =
               ctx.as.(ctx.owner)
               |> get("#{ctx.admin}/referrals?filter=review")
               |> json_response(200)

      # A credit reward lands in the member's credit ledger at once.
      assert credit_cents(referrer_membership.id) == 2_000

      drain()
      assert [%{payload: %{"reward_status" => "given"}}] = notices(ctx.member, "referral_reward")

      assert %{"invites" => [%{"reward" => %{"status" => "given"}}], "totals" => %{"paid" => 1}} =
               overview(ctx, ctx.member)

      # Approving twice is refused.
      assert ctx.as.(ctx.owner)
             |> send_json(:post, "#{ctx.admin}/referrals/#{id}/approve", %{})
             |> json_response(409)
    end

    test "the friend's gift extends their package once", ctx do
      program!(ctx)
      %{"code" => code} = overview(ctx, ctx.member)
      claim(ctx, ctx.friend, code) |> json_response(200)
      {_membership, subscription} = first_payment!(ctx, ctx.friend)
      %{id: id} = attribution(ctx, ctx.friend)

      assert %{"invite" => %{"friend_gift_applied_at" => applied}} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/referrals/#{id}/friend-gift", %{})
               |> json_response(200)

      assert applied

      extended = Repo.get!(Palee.Finance.MembershipPackageSubscription, subscription.id)
      assert Date.diff(extended.ends_on, subscription.ends_on) == 7

      assert ctx.as.(ctx.owner)
             |> send_json(:post, "#{ctx.admin}/referrals/#{id}/friend-gift", %{})
             |> json_response(409)
    end

    test "a manual reward waits for «Δόθηκε»; rejecting gives nothing", ctx do
      program!(ctx, %{reward_type: "manual", reward_value: 0, reward_note: "Μπλουζάκι"})
      %{"code" => code} = overview(ctx, ctx.member)
      claim(ctx, ctx.friend, code) |> json_response(200)
      first_payment!(ctx, ctx.friend)
      %{id: id} = attribution(ctx, ctx.friend)

      assert %{"invite" => %{"reward" => %{"status" => "approved", "note" => "Μπλουζάκι"}}} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/referrals/#{id}/approve", %{})
               |> json_response(200)

      assert %{"invite" => %{"reward" => %{"status" => "given"}}} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/referrals/#{id}/given", %{})
               |> json_response(200)

      # Another friend, rejected.
      second = user_fixture()
      %{"code" => other_code} = overview(ctx, ctx.other_member)
      claim(ctx, second, other_code) |> json_response(200)
      first_payment!(ctx, second)
      %{id: second_id} = attribution(ctx, second)

      assert %{
               "invite" => %{"reward" => %{"status" => "rejected"}, "notes" => "Ήταν ήδη πελάτης"}
             } =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/referrals/#{second_id}/reject", %{
                 note: "Ήταν ήδη πελάτης"
               })
               |> json_response(200)
    end

    test "a given discount comes off the member's next renewal, once", ctx do
      program!(ctx, %{reward_type: "discount", reward_value: 10})
      %{"code" => code} = overview(ctx, ctx.member)
      claim(ctx, ctx.friend, code) |> json_response(200)
      first_payment!(ctx, ctx.friend)
      %{id: id} = attribution(ctx, ctx.friend)

      for action <- ~w(approve given) do
        ctx.as.(ctx.owner)
        |> send_json(:post, "#{ctx.admin}/referrals/#{id}/#{action}", %{})
        |> json_response(200)
      end

      {:ok, package} =
        Finance.create_package(ctx.owner_context, %{
          name: "Μηνιαίο μέλους",
          family: "unlimited",
          billing_period: "monthly",
          base_price_cents: 6_000
        })

      membership = finance_record!(ctx, ctx.member)

      {:ok, subscription} =
        Finance.assign_package(ctx.owner_context, membership.id, package.id, %{
          ends_on: Date.add(Date.utc_today(), 30)
        })

      renew = fn start ->
        Finance.generate_renewal_invoice(ctx.owner_context, membership.id, %{
          membership_package_subscription_id: subscription.id,
          service_period_start: start
        })
      end

      assert {:ok, %{id: invoice_id, lines: [%{discount_cents: 600}]}} =
               renew.(Date.add(Date.utc_today(), 31))

      # Used once: the renewal after that is full price.
      assert {:ok, %{lines: [%{discount_cents: 0}]}} = renew.(Date.add(Date.utc_today(), 62))

      # Voiding the discounted renewal frees the reward for the next one.
      assert {:ok, _void} = Finance.void_invoice(ctx.owner_context, invoice_id, %{})

      assert {:ok, %{lines: [%{discount_cents: 600}]}} = renew.(Date.add(Date.utc_today(), 93))
    end

    test "automatic approval, the yearly cap and a programme that rewards the trial", ctx do
      program!(ctx, %{approval: "auto", yearly_cap: 1})
      %{"code" => code} = overview(ctx, ctx.member)

      [first, second] = [user_fixture(), user_fixture()]

      for friend <- [first, second] do
        claim(ctx, friend, code) |> json_response(200)
        first_payment!(ctx, friend)
      end

      assert attribution(ctx, first).status == "qualified"
      assert attribution(ctx, second).status == "capped"

      # Without a Finance record of their own the credit waits, approved.
      statuses = overview(ctx, ctx.member)["invites"] |> Enum.map(& &1["reward"]["status"])
      assert Enum.sort(statuses) == ~w(approved capped)
    end

    test "staff can give an invite to another member before it counts", ctx do
      program!(ctx)
      %{"code" => code} = overview(ctx, ctx.member)
      claim(ctx, ctx.friend, code) |> json_response(200)
      %{id: id} = attribution(ctx, ctx.friend)

      assert %{
               "invite" => %{
                 "referrer" => %{"id" => new_id},
                 "previous_referrer" => %{"id" => old_id},
                 "notes" => "Ήρθε με την Ελένη"
               }
             } =
               ctx.as.(ctx.owner)
               |> send_json(:put, "#{ctx.admin}/referrals/#{id}/referrer", %{
                 referrer_user_id: ctx.other_member.id,
                 note: "Ήρθε με την Ελένη"
               })
               |> json_response(200)

      assert {new_id, old_id} == {ctx.other_member.id, ctx.member.id}

      # Members can't run the box's invites.
      assert ctx.as.(ctx.member) |> get("#{ctx.admin}/referrals") |> json_response(403)
    end
  end
end
