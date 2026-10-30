defmodule PaleeWeb.PartnersControllerTest do
  @moduledoc """
  ADR-280 (public Partners, deck side) end to end: verification gates the
  profile, the deck and swipes; the first save needs 18+; one public deck
  with badges and distance; a mutual like makes one match with its
  conversation; undo; preferences and filters; ending, blocking and
  reporting (which blocks); the Ρυθμίσεις switch; the Palee team's reports
  queue and suspension.

  Verification is the other side's (`PartnerEligibility`); these tests
  record it straight in `partner_verifications` (ADR-280 §1 columns).
  """

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Notifications.Notification
  alias Palee.{Organizations, Repo}

  setup %{conn: conn} do
    vendor = user_fixture()
    bypass_rls(fn -> {:ok, _vendor} = Organizations.grant_vendor(vendor.id) end)

    %{
      member: user_fixture(),
      other: user_fixture(),
      third: user_fixture(),
      unverified: user_fixture(),
      vendor: vendor,
      as: fn user -> put_bearer_token(conn, user) end
    }
  end

  defp verify!(user, method \\ "membership") do
    bypass_rls(fn ->
      Repo.query!(
        """
        INSERT INTO partner_verifications (id, user_id, method, status, verified_at, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, 'verified', now(), now(), now())
        """,
        [Ecto.UUID.dump!(user.id), method]
      )
    end)

    user
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  @profile %{
    level: "intermediate",
    times: ["early", "evening"],
    goals: ["strength"],
    adult_confirmed: true
  }

  defp opt_in!(as, user, attrs \\ %{}) do
    as.(user)
    |> send_json(:put, "/api/me/partners/profile", Map.merge(@profile, attrs))
    |> json_response(200)
    |> Map.fetch!("profile")
  end

  defp deck(as, user, query \\ "") do
    as.(user) |> get("/api/me/partners/deck#{query}") |> json_response(200)
  end

  defp deck_ids(as, user, query \\ ""),
    do: as |> deck(user, query) |> Map.fetch!("cards") |> Enum.map(& &1["person"]["id"])

  defp swipe(as, user, target, direction) do
    as.(user)
    |> send_json(:post, "/api/me/partners/swipes", %{target_id: target.id, direction: direction})
  end

  defp match!(as, a, b) do
    swipe(as, a, b, "like") |> json_response(200)
    swipe(as, b, a, "like") |> json_response(200) |> Map.fetch!("match")
  end

  defp notifications(user, type),
    do: Repo.all(from(n in Notification, where: n.user_id == ^user.id and n.type == ^type))

  describe "who takes part" do
    test "the overview says what is missing; only verified people opt in, 18+ once", ctx do
      %{as: as, unverified: unverified, member: member} = ctx

      assert %{
               "eligibility" => %{"status" => status},
               "profile" => nil,
               "distance" => "needs_area",
               "options" => %{"distances_km" => [2, 5, 10, 25], "default_within_km" => 10}
             } = as.(unverified) |> get("/api/me/partners") |> json_response(200)

      assert status != "verified"

      assert %{"code" => "partner_verification_required"} =
               as.(unverified)
               |> send_json(:put, "/api/me/partners/profile", @profile)
               |> json_response(403)

      assert %{"code" => "partner_verification_required"} =
               as.(unverified) |> get("/api/me/partners/deck") |> json_response(403)

      verify!(member)

      assert %{"eligibility" => %{"status" => "verified"}} =
               as.(member) |> get("/api/me/partners") |> json_response(200)

      assert %{"code" => "partner_adult_required"} =
               as.(member)
               |> send_json(
                 :put,
                 "/api/me/partners/profile",
                 Map.delete(@profile, :adult_confirmed)
               )
               |> json_response(422)

      assert %{"adult_confirmed_at" => confirmed, "show_box" => true} = opt_in!(as, member)
      assert is_binary(confirmed)

      # Later saves keep the confirmation without asking again.
      assert %{"about" => "Hyrox", "adult_confirmed_at" => ^confirmed} =
               as.(member)
               |> send_json(:put, "/api/me/partners/profile", %{about: "Hyrox"})
               |> json_response(200)
               |> Map.fetch!("profile")
    end

    test "no deck before opting in; unverified people never show in a deck", ctx do
      %{as: as, member: member, other: other, unverified: unverified} = ctx
      verify!(member)
      verify!(other)

      assert %{"code" => "partner_profile_required"} =
               as.(member) |> get("/api/me/partners/deck") |> json_response(409)

      opt_in!(as, member)
      opt_in!(as, other)

      # A profile written before losing verification (seeded straight) never shows.
      bypass_rls(fn ->
        Repo.insert!(%Palee.Partners.Profile{
          user_id: unverified.id,
          adult_confirmed_at: DateTime.utc_now(),
          level: "intermediate",
          times: ["early"],
          goals: ["strength"]
        })
      end)

      assert deck_ids(as, member) == [other.id]
      assert swipe(as, member, unverified, "like") |> json_response(404)
    end
  end

  describe "the deck and matching" do
    test "a mutual like makes one match, tells both once, and opens their conversation", ctx do
      %{as: as, member: member, other: other, third: third} = ctx
      Enum.each([member, other, third], &verify!/1)

      opt_in!(as, member, %{about: "Hyrox in November"})
      opt_in!(as, other, %{times: ["early"], goals: ["strength", "skills"]})

      assert %{"cards" => [card], "within_km" => 10} = deck(as, member)
      assert card["person"]["id"] == other.id
      assert card["badge"] == %{"kind" => "verified", "box_name" => nil}

      assert card["shared"] == %{
               "times" => ["early"],
               "goals" => ["strength"],
               "disciplines" => [],
               "same_level" => true
             }

      refute Map.has_key?(card, "gender")

      assert %{"match" => nil} = swipe(as, member, other, "like") |> json_response(200)
      assert [] == notifications(other, :partner_match)

      # Nobody learns who liked them: the other side's card looks the same.
      assert deck_ids(as, other) == [member.id]

      assert %{
               "match" => %{
                 "id" => match_id,
                 "status" => "active",
                 "person" => %{"id" => member_id},
                 "partner_id" => member_id
               }
             } = swipe(as, other, member, "like") |> json_response(200)

      assert member_id == member.id
      assert [notice] = notifications(member, :partner_match)
      refute Map.has_key?(notice.payload, "club_name")
      assert [_] = notifications(other, :partner_match)

      # Matched people leave each other's decks.
      assert deck_ids(as, member) == []

      assert %{"matches" => [%{"id" => ^match_id, "read_only" => false, "unread" => 0}]} =
               as.(member) |> get("/api/me/partners/matches") |> json_response(200)

      assert %{"message" => %{"body" => "07:00 Thursday?", "mine" => true}} =
               as.(member)
               |> send_json(:post, "/api/me/partners/matches/#{match_id}/messages", %{
                 body: "07:00 Thursday?"
               })
               |> json_response(201)

      assert [message_notice] = notifications(other, :partner_message)
      refute inspect(message_notice.payload) =~ "Thursday"

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

      # Strangers can't read it.
      assert as.(third)
             |> get("/api/me/partners/matches/#{match_id}/messages")
             |> json_response(404)
    end

    test "passes leave the deck, undo brings them back, a match can't be undone", ctx do
      %{as: as, member: member, other: other} = ctx
      Enum.each([member, other], &verify!/1)
      opt_in!(as, member)
      opt_in!(as, other)

      swipe(as, member, other, "pass") |> json_response(200)
      assert deck_ids(as, member) == []

      assert %{"undone" => true} =
               as.(member)
               |> delete("/api/me/partners/swipes/#{other.id}")
               |> json_response(200)

      assert deck_ids(as, member) == [other.id]
      match!(as, member, other)

      assert %{"code" => "partner_already_matched"} =
               as.(member)
               |> delete("/api/me/partners/swipes/#{other.id}")
               |> json_response(409)
    end

    test "gender preferences hold both ways and filters narrow the deck", ctx do
      %{as: as, member: member, other: other, third: third} = ctx
      Enum.each([member, other, third], &verify!/1)
      opt_in!(as, member, %{gender: "woman", gender_preference: "women"})
      opt_in!(as, other, %{gender: "man"})
      opt_in!(as, third, %{gender: "woman", times: ["midday"], disciplines: ["running"]})

      assert deck_ids(as, member) == [third.id]
      assert deck_ids(as, other) == [third.id]
      assert deck_ids(as, other, "?time=evening") == []
      assert deck_ids(as, other, "?discipline=running") == [third.id]
      assert swipe(as, member, other, "like") |> json_response(404)
      assert as.(member) |> get("/api/me/partners/deck?within_km=3") |> json_response(422)
    end

    test "with an area, the deck narrows to people whose neighbourhood is near", ctx do
      %{as: as, member: member, other: other, third: third} = ctx
      Enum.each([member, other, third], &verify!/1)
      Enum.each([member, other, third], &opt_in!(as, &1))

      for {person, slug} <- [
            {member, "athens-kypseli"},
            {other, "athens-patisia"},
            {third, "athens-glyfada"}
          ] do
        as.(person)
        |> send_json(:put, "/api/me/around/area", %{neighbourhood_ids: [neighbourhood_id(slug)]})
        |> json_response(200)
      end

      assert %{"distance" => "available"} =
               as.(member) |> get("/api/me/partners") |> json_response(200)

      # Patisia is about 2 km from Kypseli, Glyfada about 15.
      assert deck_ids(as, member) == [other.id]
      assert deck_ids(as, member, "?within_km=2") == [other.id]
      assert Enum.sort(deck_ids(as, member, "?within_km=25")) == Enum.sort([other.id, third.id])
    end
  end

  defp neighbourhood_id(slug),
    do:
      Repo.one!(
        from(n in "places_neighbourhoods", where: n.slug == ^slug, select: type(n.id, :binary_id))
      )

  describe "settings, ending, blocking and reporting" do
    test "the Ρυθμίσεις switch takes someone out of every deck and back", ctx do
      %{as: as, member: member, other: other} = ctx
      Enum.each([member, other], &verify!/1)

      assert %{"visible" => false, "has_profile" => false} =
               as.(member) |> get("/api/me/partners/settings") |> json_response(200)

      opt_in!(as, member)
      opt_in!(as, other)

      assert %{"visible" => false, "has_profile" => true} =
               as.(other)
               |> send_json(:put, "/api/me/partners/settings", %{visible: false})
               |> json_response(200)

      assert deck_ids(as, member) == []

      assert %{"visible" => true} =
               as.(other)
               |> send_json(:put, "/api/me/partners/settings", %{visible: true})
               |> json_response(200)

      assert deck_ids(as, member) == [other.id]
    end

    test "ending a match keeps the conversation readable but closed", ctx do
      %{as: as, member: member, other: other} = ctx
      Enum.each([member, other], &verify!/1)
      opt_in!(as, member)
      opt_in!(as, other)
      %{"id" => match_id} = match!(as, member, other)

      assert %{"status" => "ended"} =
               as.(other) |> delete("/api/me/partners/matches/#{match_id}") |> json_response(200)

      assert %{"matches" => [%{"status" => "ended", "read_only" => true, "ended_by_me" => false}]} =
               as.(member) |> get("/api/me/partners/matches") |> json_response(200)

      assert %{"code" => "partner_match_read_only"} =
               as.(member)
               |> send_json(:post, "/api/me/partners/matches/#{match_id}/messages", %{body: "?"})
               |> json_response(409)

      assert deck_ids(as, member) == []
    end

    test "blocking ends the match and keeps both apart until unblocked", ctx do
      %{as: as, member: member, other: other} = ctx
      Enum.each([member, other], &verify!/1)
      opt_in!(as, member)
      opt_in!(as, other)
      %{"id" => match_id} = match!(as, member, other)

      as.(member)
      |> send_json(:post, "/api/me/blocks", %{user_id: other.id})
      |> json_response(200)

      assert %{"matches" => [%{"id" => ^match_id, "end_reason" => "blocked"}]} =
               as.(other) |> get("/api/me/partners/matches") |> json_response(200)

      assert deck_ids(as, other) == []
    end

    test "reporting someone blocks them and reaches the Palee team, never the gym", ctx do
      %{as: as, member: member, other: other, third: third, vendor: vendor} = ctx
      Enum.each([member, other, third], &verify!/1)
      Enum.each([member, other, third], &opt_in!(as, &1))
      %{"id" => match_id} = match!(as, member, other)

      assert %{"code" => "cannot_report_self"} =
               as.(member)
               |> send_json(:post, "/api/me/partners/reports", %{
                 target_id: member.id,
                 reason: "fake"
               })
               |> json_response(422)

      assert %{"reported" => true, "blocked" => true} =
               as.(member)
               |> send_json(:post, "/api/me/partners/reports", %{
                 target_id: other.id,
                 reason: "harassment",
                 note: "rude messages"
               })
               |> json_response(201)

      assert %{"matches" => [%{"id" => ^match_id, "end_reason" => "reported"}]} =
               as.(member) |> get("/api/me/partners/matches") |> json_response(200)

      as.(third)
      |> send_json(:post, "/api/me/partners/reports", %{target_id: other.id, reason: "fake"})
      |> json_response(201)

      # Only the Palee team sees the queue.
      assert %{"code" => "vendor_required"} =
               as.(member) |> get("/api/platform/partner-reports") |> json_response(403)

      assert %{"reports" => [first, _second]} =
               as.(vendor) |> get("/api/platform/partner-reports") |> json_response(200)

      assert first["target"]["id"] == other.id
      assert first["reports_on_target"] == 2

      assert %{"decision" => "suspend", "resolved" => 2} =
               as.(vendor)
               |> send_json(:post, "/api/platform/partner-reports/#{first["id"]}/decision", %{
                 decision: "suspend",
                 note: "two reports"
               })
               |> json_response(200)

      assert %{"code" => "partner_report_decided"} =
               as.(vendor)
               |> send_json(:post, "/api/platform/partner-reports/#{first["id"]}/decision", %{
                 decision: "dismiss"
               })
               |> json_response(409)

      assert %{"reports" => []} =
               as.(vendor) |> get("/api/platform/partner-reports") |> json_response(200)

      assert %{"reports" => [_, _]} =
               as.(vendor)
               |> get("/api/platform/partner-reports?status=actioned")
               |> json_response(200)

      # The suspended person's profile is off: only the member is left in the deck.
      assert deck_ids(as, third) == [member.id]
    end
  end
end
