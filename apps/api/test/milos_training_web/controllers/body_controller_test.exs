defmodule MilosTrainingWeb.BodyControllerTest do
  @moduledoc """
  ADR-158 (P2-M10, Σώμα) end to end under row security: snapshots in the
  person's units, weight as trend or hidden (never a number), private
  photos behind a consent, coach reads of shared snapshots (audited, photos
  only with consent, the member's display applied), delete-all, the journal
  feed and the measure reminder.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures
  import MilosTraining.TestSupport.ImageFixtures

  alias MilosTraining.Application.{BodyReminders, SweepOrphanMedia}
  alias MilosTraining.Media.AccountObject
  alias MilosTraining.Notifications.Notification
  alias MilosTraining.{Coaching, Organizations, Repo}
  alias MilosTraining.TestSupport.MemoryObjectStore

  setup %{conn: conn} do
    MemoryObjectStore.start()
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    coach = person.(:coach)
    other_coach = person.(:coach)
    member = person.(:member)

    {:ok, _} =
      Coaching.start_relationship(%{organization_id: organization.id}, %{
        coach_user_id: coach.id,
        client_user_id: member.id,
        origin: "assigned"
      })

    %{
      organization: organization,
      coach: coach,
      other_coach: other_coach,
      member: member,
      as: fn user -> put_bearer_token(conn, user) end,
      staff: "/api/org/#{Organizations.legacy_organization_slug()}/staff"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp create!(as, user, body) do
    as.(user)
    |> send_json(:post, "/api/me/body/snapshots", body)
    |> json_response(201)
    |> Map.fetch!("snapshot")
  end

  defp consent!(as, user),
    do: as.(user) |> put("/api/me/body/consents/body_photos") |> json_response(200)

  # Reserves a body photo upload and puts the bytes where the PUT would.
  defp upload!(as, user, body \\ jpeg(3000, 4000, [exif_segment()])) do
    %{"media_id" => id, "upload_url" => url} =
      as.(user)
      |> send_json(:post, "/api/me/body/photos/uploads", %{
        content_type: "image/jpeg",
        byte_size: byte_size(body)
      })
      |> json_response(200)

    [_, bucket, key] = Regex.run(~r{/upload/(media_\w+)/([^?]+)}, url)
    assert bucket == "media_private"
    assert key =~ ~r{^users/#{user.id}/media/body/#{id}/original\.jpg$}
    :ok = MemoryObjectStore.put_object(:media_private, key, body, "image/jpeg")
    id
  end

  test "snapshots are saved in SI and shown in the person's units", %{as: as, member: member} do
    assert %{
             "settings" => %{
               "units" => "metric",
               "weight_display" => "number",
               "blur_photos" => true,
               "compare_mode" => "slider"
             },
             "catalog" => [%{"key" => "weight", "unit" => "kg"} | _]
           } = as.(member) |> get("/api/me/body/settings") |> json_response(200)

    assert %{
             "settings" => %{
               "units" => "imperial",
               "blur_photos" => false,
               "compare_mode" => "side_by_side"
             },
             "catalog" => [%{"unit" => "lb"} | _]
           } =
             as.(member)
             |> send_json(:put, "/api/me/body/settings", %{
               units: "imperial",
               blur_photos: false,
               compare_mode: "side_by_side"
             })
             |> json_response(200)

    snapshot =
      create!(as, member, %{
        metrics: %{weight: 160, waist: 32.5},
        taken_at: "2026-10-01T08:00:00Z",
        notes: "  after holidays "
      })

    assert %{
             "units" => "imperial",
             "metrics" => %{"weight" => 160.0, "waist" => 32.5},
             "visibility" => "private",
             "notes" => "after holidays",
             "photos" => []
           } = snapshot

    [stored] = Repo.all(from(s in "body_snapshots", select: s.metrics))
    assert_in_delta stored["weight"], 72.575, 0.001

    # Metric values can still be sent in kg.
    assert %{"metrics" => %{"weight" => 159.8}} =
             as.(member)
             |> send_json(:patch, "/api/me/body/snapshots/#{snapshot["id"]}", %{
               units: "metric",
               metrics: %{weight: 72.5, waist: nil, hips: 96}
             })
             |> json_response(200)
             |> Map.fetch!("snapshot")

    assert %{"code" => "invalid_metric", "params" => %{"metric" => "weight"}} =
             as.(member)
             |> send_json(:post, "/api/me/body/snapshots", %{metrics: %{weight: 7000}})
             |> json_response(422)

    assert %{"code" => "snapshot_empty"} =
             as.(member)
             |> send_json(:post, "/api/me/body/snapshots", %{notes: "nothing"})
             |> json_response(422)
  end

  test "weight as trend or hidden never leaves the server as a number", %{as: as, member: member} do
    first =
      create!(as, member, %{metrics: %{weight: 75.0, waist: 84}, taken_at: "2026-08-01T08:00:00Z"})

    for {weight, day} <- [{74.2, "08"}, {73.4, "15"}, {72.6, "22"}, {71.8, "29"}] do
      create!(as, member, %{metrics: %{weight: weight}, taken_at: "2026-08-#{day}T08:00:00Z"})
    end

    last =
      create!(as, member, %{metrics: %{weight: 71.0, waist: 81}, taken_at: "2026-09-05T08:00:00Z"})

    assert %{"display" => "number", "trend" => "down", "points" => [_ | _] = points} =
             as.(member)
             |> get("/api/me/body/series?metric=weight&range=all")
             |> json_response(200)

    assert length(points) == 6

    as.(member)
    |> send_json(:put, "/api/me/body/settings", %{weight_display: "trend"})
    |> json_response(200)

    list = as.(member) |> get("/api/me/body/snapshots") |> json_response(200)
    encoded = Jason.encode!(list)
    refute encoded =~ "75.0"
    refute encoded =~ "71.0"

    assert [%{"metrics" => %{"waist" => 81.0} = shown, "withheld_metrics" => ["weight"]} | _] =
             list["snapshots"]

    refute Map.has_key?(shown, "weight")

    assert %{"display" => "trend", "trend" => "down", "points" => [], "shape" => shape} =
             as.(member)
             |> get("/api/me/body/series?metric=weight&range=all")
             |> json_response(200)

    # The trend line is real data with no scale: 0..1, oldest highest here.
    assert length(shape) == 6
    assert hd(shape)["y"] == 1.0 and List.last(shape)["y"] == 0.0
    refute Jason.encode!(shape) =~ "75.0"

    assert %{"deltas" => deltas} =
             as.(member)
             |> get("/api/me/body/compare?from=#{last["id"]}&to=#{first["id"]}")
             |> json_response(200)

    assert [
             %{"metric" => "weight", "delta" => nil, "direction" => "down"},
             %{"metric" => "waist", "delta" => -3.0}
           ] = deltas

    as.(member)
    |> send_json(:put, "/api/me/body/settings", %{weight_display: "hidden"})
    |> json_response(200)

    hidden =
      as.(member)
      |> get("/api/me/body/series?metric=weight&range=all")
      |> json_response(200)

    assert %{"display" => "hidden", "trend" => nil, "points" => []} = hidden
    refute Map.has_key?(hidden, "shape")

    assert %{"deltas" => [%{"metric" => "waist"}]} =
             as.(member)
             |> get("/api/me/body/compare?from=#{first["id"]}&to=#{last["id"]}")
             |> json_response(200)

    assert %{"withheld_metrics" => [], "metrics" => metrics} =
             as.(member)
             |> get("/api/me/body/snapshots/#{last["id"]}")
             |> json_response(200)
             |> Map.fetch!("snapshot")

    assert metrics == %{"waist" => 81.0}
  end

  test "photos need consent, are stripped, private and signed for the owner", ctx do
    %{as: as, member: member} = ctx

    assert %{"code" => "body_photo_consent_required"} =
             as.(member)
             |> send_json(:post, "/api/me/body/photos/uploads", %{
               content_type: "image/jpeg",
               byte_size: 10
             })
             |> json_response(403)

    assert %{"consents" => [%{"scope" => "body_photos", "active" => true} | _]} =
             consent!(as, member)

    front = upload!(as, member)
    side = upload!(as, member)

    snapshot =
      create!(as, member, %{
        photos: [%{media_id: front, pose: "front"}, %{media_id: side, pose: "side"}],
        visibility: "coach_full"
      })

    assert %{"metrics" => %{}, "photo_count" => 2, "photos" => [photo, _]} = snapshot

    assert %{"pose" => "front", "status" => "ready", "thumb_url" => thumb, "full_url" => full} =
             photo

    assert thumb =~ "media_private/users/#{member.id}/media/body/#{front}/thumb.webp"
    assert full =~ "/full.webp"

    # The next snapshot starts from the visibility used last.
    assert %{"settings" => %{"default_visibility" => "coach_full"}} =
             as.(member) |> get("/api/me/body/settings") |> json_response(200)

    # The upload is attached and no longer usable elsewhere.
    assert %{"code" => "invalid_media"} =
             as.(member)
             |> send_json(:post, "/api/me/body/snapshots", %{
               photos: [%{media_id: front, pose: "back"}]
             })
             |> json_response(422)

    assert %{"code" => "pose_taken"} =
             as.(member)
             |> send_json(:post, "/api/me/body/snapshots/#{snapshot["id"]}/photos", %{
               media_id: upload!(as, member),
               pose: "front"
             })
             |> json_response(409)

    assert %{"photos" => latest} =
             as.(member) |> get("/api/me/body/photos/latest") |> json_response(200)

    assert latest |> Enum.map(& &1["pose"]) |> Enum.sort() == ~w(front side)

    # A body photo never passes as a post photo.
    assert as.(member) |> get("/api/me/media/#{front}") |> json_response(404)

    # Removing photos keeps at least one photo on a snapshot without metrics.
    [_, side_photo] = snapshot["photos"]

    assert as.(member)
           |> delete("/api/me/body/snapshots/#{snapshot["id"]}/photos/#{photo["id"]}")
           |> response(204)

    assert %{"code" => "snapshot_empty"} =
             as.(member)
             |> delete("/api/me/body/snapshots/#{snapshot["id"]}/photos/#{side_photo["id"]}")
             |> json_response(422)

    refute Repo.exists?(from(m in AccountObject, where: m.id == ^front))

    # The daily dangling sweep knows body photos belong to their snapshot.
    {:ok, _count} =
      SweepOrphanMedia.call(DateTime.add(DateTime.utc_now(), 2, :day), dangling: true)

    assert Repo.exists?(from(m in AccountObject, where: m.id == ^side))
  end

  test "delete all photos purges files and snapshots left empty", %{as: as, member: member} do
    consent!(as, member)

    only_photos =
      create!(as, member, %{photos: [%{media_id: upload!(as, member), pose: "front"}]})

    with_metrics =
      create!(as, member, %{
        metrics: %{weight: 70},
        photos: [%{media_id: upload!(as, member), pose: "back"}]
      })

    _unattached = upload!(as, member)

    assert %{"deleted_photos" => 3, "deleted_snapshots" => 1} =
             as.(member) |> delete("/api/me/body/photos") |> json_response(200)

    assert {:ok, []} =
             MemoryObjectStore.list_objects(:media_private, "users/#{member.id}/media/body/")

    assert as.(member) |> get("/api/me/body/snapshots/#{only_photos["id"]}") |> json_response(404)

    assert %{"photos" => [], "metrics" => %{"weight" => 70.0}} =
             as.(member)
             |> get("/api/me/body/snapshots/#{with_metrics["id"]}")
             |> json_response(200)
             |> Map.fetch!("snapshot")
  end

  test "a coach reads only shared snapshots, photos only with consent, every read logged", ctx do
    %{as: as, member: member, coach: coach, staff: staff} = ctx
    path = "#{staff}/clients/#{member.id}/body"
    consent!(as, member)

    _private = create!(as, member, %{metrics: %{waist: 90}, taken_at: "2026-09-01T08:00:00Z"})

    numbers =
      create!(as, member, %{
        metrics: %{weight: 72.4, waist: 81},
        notes: "felt bloated",
        visibility: "coach_numbers",
        photos: [%{media_id: upload!(as, member), pose: "front"}],
        taken_at: "2026-09-10T08:00:00Z"
      })

    full =
      create!(as, member, %{
        metrics: %{weight: 72.0},
        visibility: "coach_full",
        photos: [%{media_id: upload!(as, member), pose: "front"}],
        taken_at: "2026-09-20T08:00:00Z"
      })

    assert %{"snapshots" => [seen_full, seen_numbers], "next_cursor" => nil} =
             as.(coach) |> get(path) |> json_response(200)

    assert seen_full["id"] == full["id"]
    assert [%{"full_url" => url}] = seen_full["photos"]
    assert url =~ "media_private/users/#{member.id}/media/body/"
    assert seen_numbers["id"] == numbers["id"]
    assert seen_numbers["photos"] == [] and seen_numbers["photo_count"] == 0
    assert seen_numbers["notes"] == nil
    assert seen_numbers["metrics"] == %{"weight" => 72.4, "waist" => 81.0}

    # Withdrawing consent hides the photos at once.
    as.(member) |> delete("/api/me/body/consents/body_photos") |> json_response(200)

    assert %{"snapshot" => %{"photos" => []}} =
             as.(coach) |> get("#{path}/snapshots/#{full["id"]}") |> json_response(200)

    # The member's display choice applies to the coach too.
    as.(member)
    |> send_json(:put, "/api/me/body/settings", %{weight_display: "hidden"})
    |> json_response(200)

    assert %{"snapshots" => [hidden_full, hidden_numbers]} =
             as.(coach) |> get(path) |> json_response(200)

    assert hidden_full["metrics"] == %{}
    assert hidden_numbers["metrics"] == %{"waist" => 81.0}

    # A private snapshot does not exist for the coach.
    assert as.(coach)
           |> get("#{path}/snapshots/#{Ecto.UUID.generate()}")
           |> json_response(404)

    # Another coach without this client is refused.
    assert as.(ctx.other_coach) |> get(path) |> json_response(403)
    # A member is not staff.
    assert as.(member) |> get(path) |> json_response(403)

    assert %{"entries" => entries} =
             as.(member) |> get("/api/me/body/access-log") |> json_response(200)

    assert [
             %{"subject" => "list", "photos_shown" => false},
             %{"subject" => "snapshot", "photos_shown" => false},
             %{"subject" => "list", "photos_shown" => true, "snapshot_ids" => ids} = first
           ] = entries

    assert first["reader"]["id"] == coach.id
    assert first["organization"]["id"] == ctx.organization.id
    assert Enum.sort(ids) == Enum.sort([full["id"], numbers["id"]])
  end

  test "a coach reads a client's series from shared snapshots, as the client's display allows",
       ctx do
    %{as: as, member: member, coach: coach, staff: staff} = ctx
    path = "#{staff}/clients/#{member.id}/body/series"

    _private = create!(as, member, %{metrics: %{weight: 90.0}, taken_at: "2026-08-01T08:00:00Z"})

    shared =
      for {weight, day} <- [{75.0, "10"}, {74.0, "17"}, {73.0, "24"}] do
        create!(as, member, %{
          metrics: %{weight: weight},
          visibility: "coach_numbers",
          taken_at: "2026-08-#{day}T08:00:00Z"
        })
      end

    assert %{"display" => "number", "metric" => "weight", "range" => "all", "points" => points} =
             as.(coach) |> get("#{path}?metric=weight&range=all") |> json_response(200)

    # Only the shared snapshots: the private 90 kg never reaches the coach.
    assert Enum.map(points, & &1["value"]) == [75.0, 74.0, 73.0]

    as.(member)
    |> send_json(:put, "/api/me/body/settings", %{weight_display: "trend"})
    |> json_response(200)

    trend = as.(coach) |> get("#{path}?metric=weight&range=all") |> json_response(200)
    assert %{"display" => "trend", "points" => [], "shape" => [_, _, _] = shape} = trend
    assert Enum.map(shape, & &1["y"]) |> hd() == 1.0
    refute Jason.encode!(trend) =~ "75.0"

    as.(member)
    |> send_json(:put, "/api/me/body/settings", %{weight_display: "hidden"})
    |> json_response(200)

    hidden = as.(coach) |> get("#{path}?metric=weight&range=all") |> json_response(200)
    assert %{"display" => "hidden", "points" => []} = hidden
    refute Map.has_key?(hidden, "shape")

    # Unknown metrics are refused by the contract; access as for the other routes.
    assert as.(coach) |> get("#{path}?metric=height") |> json_response(422)
    assert as.(ctx.other_coach) |> get("#{path}?metric=weight") |> json_response(403)
    assert as.(member) |> get("#{path}?metric=weight") |> json_response(403)

    assert %{"entries" => entries} =
             as.(member) |> get("/api/me/body/access-log") |> json_response(200)

    assert [
             %{"subject" => "series", "snapshot_ids" => []},
             %{"subject" => "series", "snapshot_ids" => trend_ids},
             %{"subject" => "series", "snapshot_ids" => number_ids, "photos_shown" => false}
           ] = entries

    assert Enum.sort(number_ids) == Enum.sort(Enum.map(shared, & &1["id"]))
    assert Enum.sort(trend_ids) == Enum.sort(number_ids)
  end

  test "body snapshots appear only in the member's own journal", ctx do
    %{as: as, member: member, coach: coach, staff: staff} = ctx

    snapshot =
      create!(as, member, %{metrics: %{waist: 80}, visibility: "coach_numbers"})

    assert %{
             "items" => [
               %{
                 "kind" => "body",
                 "id" => id,
                 "journal_visibility" => "coach_can_view",
                 "choosable_visibilities" => []
               }
             ]
           } =
             as.(member) |> get("/api/me/journal?kinds=body") |> json_response(200)

    assert id == snapshot["id"]

    assert %{"items" => items} =
             as.(coach) |> get("#{staff}/clients/#{member.id}/journal") |> json_response(200)

    refute Enum.any?(items, &(&1["kind"] == "body"))

    assert %{"code" => "visibility_not_allowed"} =
             as.(member)
             |> send_json(:put, "/api/me/journal/entries/body/#{id}/visibility", %{
               visibility: "private"
             })
             |> json_response(422)

    # Switching the section off hides it from the feed.
    as.(member)
    |> send_json(:put, "/api/me/body/settings", %{journal_sections: %{body: false}})
    |> json_response(200)

    assert %{"items" => []} =
             as.(member) |> get("/api/me/journal?kinds=body") |> json_response(200)
  end

  test "the measure reminder is opt-in and sent once when due", %{as: as, member: member} do
    create!(as, member, %{metrics: %{waist: 80}})
    now = DateTime.utc_now()

    assert :ok = BodyReminders.call(DateTime.add(now, 60, :day))
    refute reminded?(member)

    as.(member)
    |> send_json(:put, "/api/me/body/settings", %{measure_reminder_weeks: 2})
    |> json_response(200)

    assert :ok = BodyReminders.call(DateTime.add(now, 7, :day))
    refute reminded?(member)

    later = DateTime.add(now, 15, :day)
    assert :ok = BodyReminders.call(later)
    assert reminded?(member)
    assert :ok = BodyReminders.call(later)

    assert 1 ==
             Repo.aggregate(
               from(n in Notification,
                 where: n.user_id == ^member.id and n.type == :body_measure_reminder
               ),
               :count
             )
  end

  test "consents are listed per scope and validated", %{as: as, member: member} do
    assert %{
             "consents" => [
               %{"scope" => "body_photos", "active" => false},
               %{"scope" => "health_data"}
             ]
           } =
             as.(member) |> get("/api/me/body/consents") |> json_response(200)

    assert as.(member) |> put("/api/me/body/consents/everything") |> json_response(422)
  end

  describe "sharing a before/after" do
    setup %{as: as, member: member} do
      consent!(as, member)

      before =
        create!(as, member, %{
          metrics: %{weight: 80},
          photos: [%{media_id: upload!(as, member), pose: "front"}],
          taken_at: "2026-07-01T08:00:00Z"
        })

      later =
        create!(as, member, %{
          metrics: %{weight: 74},
          photos: [%{media_id: upload!(as, member), pose: "front"}],
          taken_at: "2026-10-01T08:00:00Z"
        })

      %{before: before, later: later}
    end

    defp share(as, user, body, status) do
      as.(user)
      |> send_json(:post, "/api/me/body/share", body)
      |> json_response(status)
    end

    test "needs an explicit confirmation and the consent", ctx do
      %{as: as, member: member} = ctx

      body = %{
        from_snapshot_id: ctx.before["id"],
        to_snapshot_id: ctx.later["id"],
        pose: "front",
        audience: "followers"
      }

      # Without confirm the request is refused before anything happens.
      share(as, member, body, 422)

      assert %{"code" => "share_confirmation_required"} =
               share(as, member, Map.put(body, :confirm, false), 422)

      as.(member) |> delete("/api/me/body/consents/body_photos") |> json_response(200)

      assert %{"code" => "body_photo_consent_required"} =
               share(as, member, Map.put(body, :confirm, true), 403)

      refute Repo.exists?(from(m in AccountObject, where: m.purpose == "post_photo"))
    end

    test "only your own snapshots", ctx do
      %{as: as, coach: coach} = ctx
      consent!(as, coach)

      assert share(
               as,
               coach,
               %{
                 from_snapshot_id: ctx.before["id"],
                 to_snapshot_id: ctx.later["id"],
                 pose: "front",
                 audience: "followers",
                 confirm: true
               },
               404
             )
    end

    test "copies the photos into a post, older first, with no numbers", ctx do
      %{as: as, member: member} = ctx

      assert %{"post" => post} =
               share(
                 as,
                 member,
                 %{
                   from_snapshot_id: ctx.later["id"],
                   to_snapshot_id: ctx.before["id"],
                   pose: "front",
                   audience: "followers",
                   text: "Three months",
                   confirm: true
                 },
                 201
               )

      assert post["body"] == "Three months"
      assert [first, second] = post["media"]
      assert first["full_url"] =~ "/media/posts/"
      refute Jason.encode!(post) =~ "/media/body/"

      copies =
        Repo.all(from(m in AccountObject, where: m.purpose == "post_photo", select: m.id))

      assert Enum.sort(copies) == Enum.sort([first["id"], second["id"]])
      [before_photo] = ctx.before["photos"]
      refute first["id"] == before_photo["id"]

      # Deleting every body photo leaves the post whole.
      as.(member) |> delete("/api/me/body/photos") |> json_response(200)

      assert {:ok, [_ | _]} =
               MemoryObjectStore.list_objects(:media_private, "users/#{member.id}/media/posts/")

      assert Repo.aggregate(from(m in AccountObject, where: m.purpose == "post_photo"), :count) ==
               2
    end
  end

  defp reminded?(user) do
    Repo.exists?(
      from(n in Notification, where: n.user_id == ^user.id and n.type == :body_measure_reminder)
    )
  end
end
