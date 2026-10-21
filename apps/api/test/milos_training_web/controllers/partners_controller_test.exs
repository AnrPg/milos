defmodule MilosTrainingWeb.PartnersControllerTest do
  @moduledoc """
  ADR-169 (P3-M7, Partners) end to end: opting in per club, the deck, a
  mutual like making one match with its conversation, undo, preferences
  and filters, which clubs offer Partners, ending, blocking and reporting,
  «Κλείστε μαζί» and the Ρυθμίσεις switch.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Notifications.Notification
  alias MilosTraining.Organizations.OrganizationMembership, as: Membership
  alias MilosTraining.{Organizations, Repo, Scheduling}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    slug = Organizations.legacy_organization_slug()

    %{
      organization: organization,
      admin: person.(:admin),
      member: person.(:member),
      other: person.(:member),
      third: person.(:member),
      outsider: user_fixture(),
      as: fn user -> put_bearer_token(conn, user) end,
      staff: "/api/org/#{slug}/admin/community"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp gym_club_id(as, user) do
    as.(user)
    |> get("/api/me/clubs")
    |> json_response(200)
    |> Map.fetch!("clubs")
    |> Enum.find(&(&1["kind"] == "gym"))
    |> Map.fetch!("id")
  end

  @profile %{level: "intermediate", times: ["early", "evening"], goals: ["strength"]}

  defp opt_in!(as, user, club_id, attrs \\ %{}) do
    as.(user)
    |> send_json(:put, "/api/me/clubs/#{club_id}/partners/profile", Map.merge(@profile, attrs))
    |> json_response(200)
    |> Map.fetch!("profile")
  end

  defp deck_ids(as, user, club_id, query \\ "") do
    as.(user)
    |> get("/api/me/clubs/#{club_id}/partners/deck#{query}")
    |> json_response(200)
    |> Map.fetch!("cards")
    |> Enum.map(& &1["person"]["id"])
  end

  defp swipe(as, user, club_id, target, direction) do
    as.(user)
    |> send_json(:post, "/api/me/clubs/#{club_id}/partners/swipes", %{
      target_id: target.id,
      direction: direction
    })
  end

  defp match!(as, a, b, club_id) do
    swipe(as, a, club_id, b, "like") |> json_response(200)
    swipe(as, b, club_id, a, "like") |> json_response(200) |> Map.fetch!("match")
  end

  defp notifications(user, type),
    do: Repo.all(from(n in Notification, where: n.user_id == ^user.id and n.type == ^type))

  describe "opting in and matching" do
    test "a mutual like makes one match, tells both once, and opens their conversation", ctx do
      %{as: as, member: member, other: other} = ctx
      club_id = gym_club_id(as, member)

      assert %{
               "offered" => true,
               "member" => true,
               "profile" => nil,
               "options" => %{"times" => times}
             } =
               as.(member) |> get("/api/me/clubs/#{club_id}/partners") |> json_response(200)

      assert "early" in times

      # No deck before opting in.
      assert %{"code" => "partner_profile_required"} =
               as.(member) |> get("/api/me/clubs/#{club_id}/partners/deck") |> json_response(409)

      opt_in!(as, member, club_id, %{about: "Hyrox in November"})
      opt_in!(as, other, club_id, %{times: ["early"], goals: ["strength", "skills"]})

      assert %{"cards" => [card]} =
               as.(member) |> get("/api/me/clubs/#{club_id}/partners/deck") |> json_response(200)

      assert card["person"]["id"] == other.id

      assert card["shared"] == %{
               "times" => ["early"],
               "goals" => ["strength"],
               "same_level" => true
             }

      refute Map.has_key?(card, "gender")

      assert %{"match" => nil} = swipe(as, member, club_id, other, "like") |> json_response(200)
      assert [] == notifications(other, :partner_match)

      # Nobody learns who liked them: the other side's card looks the same.
      assert deck_ids(as, other, club_id) == [member.id]

      assert %{
               "match" => %{
                 "id" => match_id,
                 "status" => "active",
                 "person" => %{"id" => member_id}
               }
             } =
               swipe(as, other, club_id, member, "like") |> json_response(200)

      assert member_id == member.id
      assert [_] = notifications(member, :partner_match)
      assert [_] = notifications(other, :partner_match)

      # Matched people leave each other's decks.
      assert deck_ids(as, member, club_id) == []

      assert %{
               "matches" => [
                 %{
                   "id" => ^match_id,
                   "read_only" => false,
                   "unread" => 0,
                   "plannable" => true,
                   "partner_profile_id" => partner_profile_id
                 }
               ]
             } =
               as.(member) |> get("/api/me/partners/matches") |> json_response(200)

      # What a report from the conversation names.
      assert partner_profile_id == card["profile_id"]

      assert %{"message" => %{"body" => "07:00 Thursday?", "mine" => true}} =
               as.(member)
               |> send_json(:post, "/api/me/partners/matches/#{match_id}/messages", %{
                 body: "07:00 Thursday?"
               })
               |> json_response(201)

      assert [notice] = notifications(other, :partner_message)
      refute inspect(notice.payload) =~ "Thursday"

      assert %{"matches" => [%{"unread" => 1}]} =
               as.(other) |> get("/api/me/partners/matches") |> json_response(200)

      assert %{
               "messages" => [%{"body" => "07:00 Thursday?", "mine" => false}],
               "read_only" => false
             } =
               as.(other)
               |> get("/api/me/partners/matches/#{match_id}/messages")
               |> json_response(200)

      assert %{"read" => 1} =
               as.(other)
               |> post("/api/me/partners/matches/#{match_id}/messages/read")
               |> json_response(200)

      assert %{"matches" => [%{"unread" => 0}]} =
               as.(other) |> get("/api/me/partners/matches") |> json_response(200)

      # Strangers can't read it.
      assert as.(ctx.third)
             |> get("/api/me/partners/matches/#{match_id}/messages")
             |> json_response(404)
    end

    test "passes leave the deck, undo brings them back, a match can't be undone", ctx do
      %{as: as, member: member, other: other} = ctx
      club_id = gym_club_id(as, member)
      opt_in!(as, member, club_id)
      opt_in!(as, other, club_id)

      swipe(as, member, club_id, other, "pass") |> json_response(200)
      assert deck_ids(as, member, club_id) == []

      assert %{"undone" => true} =
               as.(member)
               |> delete("/api/me/clubs/#{club_id}/partners/swipes/#{other.id}")
               |> json_response(200)

      assert deck_ids(as, member, club_id) == [other.id]

      match!(as, member, other, club_id)

      assert %{"code" => "partner_already_matched"} =
               as.(member)
               |> delete("/api/me/clubs/#{club_id}/partners/swipes/#{other.id}")
               |> json_response(409)
    end

    test "gender preferences hold both ways and filters narrow the deck", ctx do
      %{as: as, member: member, other: other, third: third} = ctx
      club_id = gym_club_id(as, member)
      opt_in!(as, member, club_id, %{gender: "woman", gender_preference: "women"})
      opt_in!(as, other, club_id, %{gender: "man"})
      opt_in!(as, third, club_id, %{gender: "woman", times: ["midday"]})

      assert deck_ids(as, member, club_id) == [third.id]
      # The preference holds from the other side too.
      assert deck_ids(as, other, club_id) == [third.id]
      assert deck_ids(as, other, club_id, "?time=evening") == []

      # Swiping someone outside the preference is refused like a missing person.
      assert swipe(as, member, club_id, other, "like") |> json_response(404)
    end
  end

  describe "who takes part" do
    test "only members of a verified club, and only while the gym has Partners on", ctx do
      %{as: as, member: member, admin: admin, outsider: outsider, staff: staff} = ctx
      club_id = gym_club_id(as, member)

      assert as.(outsider)
             |> send_json(:put, "/api/me/clubs/#{club_id}/partners/profile", @profile)
             |> json_response(404)

      %{"club" => %{"id" => open_id}} =
        as.(admin)
        |> send_json(:post, "#{staff}/clubs", %{name: "Sunday walk", join_policy: "open"})
        |> json_response(201)

      as.(member) |> post("/api/me/open-clubs/#{open_id}/membership") |> json_response(200)

      assert %{"offered" => false, "unavailable_reason" => "not_offered"} =
               as.(member) |> get("/api/me/clubs/#{open_id}/partners") |> json_response(200)

      assert %{"code" => "partners_not_offered"} =
               as.(member)
               |> send_json(:put, "/api/me/clubs/#{open_id}/partners/profile", @profile)
               |> json_response(403)

      assert %{"partners_enabled" => false} =
               as.(admin)
               |> send_json(:put, "#{staff}/settings", %{partners_enabled: false})
               |> json_response(200)

      assert %{"offered" => false, "unavailable_reason" => "disabled"} =
               as.(member) |> get("/api/me/clubs/#{club_id}/partners") |> json_response(200)

      # The group rule the gym chose earlier stays as it was.
      assert %{"member_groups" => "approval", "partners_enabled" => true} =
               as.(admin)
               |> send_json(:put, "#{staff}/settings", %{partners_enabled: true})
               |> json_response(200)
    end

    test "leaving the gym takes someone out of decks and makes the conversation read-only", ctx do
      %{as: as, member: member, other: other, third: third, organization: organization} = ctx
      club_id = gym_club_id(as, member)
      opt_in!(as, member, club_id)
      opt_in!(as, other, club_id)
      opt_in!(as, third, club_id)
      %{"id" => match_id} = match!(as, member, other, club_id)

      Repo.update_all(
        from(m in Membership,
          where: m.user_id == ^other.id and m.organization_id == ^organization.id
        ),
        set: [status: :suspended]
      )

      assert deck_ids(as, third, club_id) == [member.id]

      assert %{"read_only" => true} =
               as.(member)
               |> get("/api/me/partners/matches/#{match_id}/messages")
               |> json_response(200)

      assert %{"code" => "partner_match_read_only"} =
               as.(member)
               |> send_json(:post, "/api/me/partners/matches/#{match_id}/messages", %{body: "hi"})
               |> json_response(409)
    end
  end

  describe "ending, blocking and reporting" do
    test "ending a match keeps the conversation readable but closed", ctx do
      %{as: as, member: member, other: other} = ctx
      club_id = gym_club_id(as, member)
      opt_in!(as, member, club_id)
      opt_in!(as, other, club_id)
      %{"id" => match_id} = match!(as, member, other, club_id)

      assert %{"status" => "ended"} =
               as.(other) |> delete("/api/me/partners/matches/#{match_id}") |> json_response(200)

      assert %{"matches" => [%{"status" => "ended", "read_only" => true, "ended_by_me" => false}]} =
               as.(member) |> get("/api/me/partners/matches") |> json_response(200)

      assert as.(member)
             |> send_json(:post, "/api/me/partners/matches/#{match_id}/messages", %{body: "?"})
             |> json_response(409)

      # They liked each other already: they don't meet in the deck again.
      assert deck_ids(as, member, club_id) == []
    end

    test "blocking ends the match and keeps both apart until unblocked", ctx do
      %{as: as, member: member, other: other, third: third} = ctx
      club_id = gym_club_id(as, member)
      opt_in!(as, member, club_id)
      opt_in!(as, other, club_id)
      opt_in!(as, third, club_id)
      match!(as, member, other, club_id)

      assert %{"blocked" => true} =
               as.(member)
               |> send_json(:post, "/api/me/blocks", %{user_id: third.id})
               |> json_response(200)

      assert %{"blocked" => true} =
               as.(member)
               |> send_json(:post, "/api/me/blocks", %{user_id: other.id})
               |> json_response(200)

      assert %{"matches" => [%{"status" => "ended", "end_reason" => "blocked"}]} =
               as.(other) |> get("/api/me/partners/matches") |> json_response(200)

      refute member.id in deck_ids(as, third, club_id)
      assert deck_ids(as, member, club_id) == []

      assert %{"blocks" => blocks} = as.(member) |> get("/api/me/blocks") |> json_response(200)
      assert Enum.sort(Enum.map(blocks, & &1["person"]["id"])) == Enum.sort([other.id, third.id])
      assert %{"blocks" => []} = as.(third) |> get("/api/me/blocks") |> json_response(200)

      assert as.(member) |> delete("/api/me/blocks/#{third.id}") |> json_response(200)
      assert member.id in deck_ids(as, third, club_id)

      assert %{"code" => "cannot_block_self"} =
               as.(member)
               |> send_json(:post, "/api/me/blocks", %{user_id: member.id})
               |> json_response(422)
    end

    test "a report blocks the person for the reporter; staff hide the profile", ctx do
      %{as: as, member: member, other: other, third: third, admin: admin, staff: staff} = ctx
      club_id = gym_club_id(as, member)
      opt_in!(as, member, club_id)
      %{"id" => profile_id} = opt_in!(as, other, club_id, %{about: "rude words"})
      opt_in!(as, third, club_id)
      %{"id" => match_id} = match!(as, third, other, club_id)

      as.(member)
      |> send_json(:post, "/api/me/community/reports", %{
        target_type: "partner",
        target_id: profile_id,
        reason: "harassment"
      })
      |> json_response(201)

      assert deck_ids(as, member, club_id) == [third.id]
      assert [_ | _] = notifications(admin, :community_report_created)

      assert %{
               "reports" => [
                 %{"target_type" => "partner", "preview" => %{"body" => "rude words"}}
               ]
             } =
               as.(admin) |> get("#{staff}/reports") |> json_response(200)

      as.(admin)
      |> send_json(:post, "#{staff}/reports/actions", %{
        target_type: "partner",
        target_id: profile_id,
        action: "hide"
      })
      |> json_response(200)

      assert %{"matches" => [%{"id" => ^match_id, "status" => "ended", "end_reason" => "hidden"}]} =
               as.(third) |> get("/api/me/partners/matches") |> json_response(200)

      assert %{"profile" => %{"suspended" => true, "active" => false}} =
               as.(other) |> get("/api/me/clubs/#{club_id}/partners") |> json_response(200)

      assert %{"code" => "partner_profile_suspended"} =
               as.(other)
               |> send_json(:put, "/api/me/clubs/#{club_id}/partners/profile", %{active: true})
               |> json_response(403)
    end
  end

  describe "«Κλείστε μαζί»" do
    test "the gym's next classes, the ones a partner booked first; a plan posts the class", ctx do
      %{as: as, member: member, other: other, admin: admin, organization: organization} = ctx
      club_id = gym_club_id(as, member)
      opt_in!(as, member, club_id)
      opt_in!(as, other, club_id)
      %{"id" => match_id} = match!(as, member, other, club_id)

      workout = workout_fixture(admin)

      soon =
        slot_fixture(workout, %{
          scheduled_at:
            DateTime.add(DateTime.utc_now(), 2 * 3600, :second) |> DateTime.truncate(:second)
        })

      later =
        slot_fixture(workout, %{
          scheduled_at:
            DateTime.add(DateTime.utc_now(), 2 * 86_400, :second) |> DateTime.truncate(:second)
        })

      tenant = %{organization_id: organization.id, user_id: other.id}
      {:ok, _booking} = Scheduling.submit_auto_approved_booking(tenant, other.id, later.id)

      assert %{"available" => true, "sessions" => [first, second | _]} =
               as.(member)
               |> get("/api/me/partners/matches/#{match_id}/sessions")
               |> json_response(200)

      assert %{"class_id" => later_id, "booked_by_partner" => true, "booked_by_me" => false} =
               first

      assert later_id == later.id
      assert second["class_id"] == soon.id

      assert %{
               "message" => %{
                 "kind" => "plan",
                 "plan" => %{"class_id" => ^later_id},
                 "body" => "Join me?"
               }
             } =
               as.(member)
               |> send_json(:post, "/api/me/partners/matches/#{match_id}/plans", %{
                 class_id: later.id,
                 body: "Join me?"
               })
               |> json_response(201)

      assert %{"messages" => [%{"kind" => "plan", "mine" => false}]} =
               as.(other)
               |> get("/api/me/partners/matches/#{match_id}/messages")
               |> json_response(200)
    end
  end

  describe "Ρυθμίσεις" do
    test "the switch pauses and resumes every profile", ctx do
      %{as: as, member: member, other: other} = ctx
      club_id = gym_club_id(as, member)
      opt_in!(as, member, club_id)
      opt_in!(as, other, club_id)

      assert %{"visible" => true, "clubs" => 1} =
               as.(member) |> get("/api/me/partners/settings") |> json_response(200)

      assert %{"visible" => false} =
               as.(member)
               |> send_json(:put, "/api/me/partners/settings", %{visible: false})
               |> json_response(200)

      assert deck_ids(as, other, club_id) == []

      assert %{"visible" => true} =
               as.(member)
               |> send_json(:put, "/api/me/partners/settings", %{visible: true})
               |> json_response(200)

      assert deck_ids(as, other, club_id) == [member.id]
    end
  end
end
