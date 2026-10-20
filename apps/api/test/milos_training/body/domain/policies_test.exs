defmodule MilosTraining.Body.Domain.PoliciesTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Body.Domain.{ConsentPolicy, SettingsPolicy, SnapshotCursor, SnapshotPolicy}

  describe "snapshots" do
    test "need one metric or one photo" do
      assert :ok = SnapshotPolicy.validate_content(%{"weight" => 70.0}, 0)
      assert :ok = SnapshotPolicy.validate_content(%{}, 1)
      assert {:error, :snapshot_empty} = SnapshotPolicy.validate_content(%{}, 0)
    end

    test "photos: up to four, front/side/back once each" do
      assert :ok = SnapshotPolicy.validate_photos([], ~w(front side back other))

      assert {:error, :too_many_body_photos} =
               SnapshotPolicy.validate_photos(~w(front side back), ~w(other other))

      assert {:error, :pose_taken} = SnapshotPolicy.validate_photos(["front"], ["front"])
      assert :ok = SnapshotPolicy.validate_photos(["other"], ["other"])
      assert {:error, :invalid_pose} = SnapshotPolicy.validate_photos([], ["top"])
    end

    test "visibility and notes" do
      assert :ok = SnapshotPolicy.validate_visibility("coach_full")
      assert {:error, :invalid_body_visibility} = SnapshotPolicy.validate_visibility("public")
      refute SnapshotPolicy.shared?("private")
      assert SnapshotPolicy.shared?("coach_numbers")
      assert {:ok, nil} = SnapshotPolicy.normalize_notes("   ")
      assert {:ok, "ok"} = SnapshotPolicy.normalize_notes(" ok ")

      assert {:error, :body_notes_too_long} =
               SnapshotPolicy.normalize_notes(String.duplicate("a", 2001))
    end
  end

  describe "consents" do
    test "photos need an active grant; a withdrawn one does not count" do
      granted = %{scope: "body_photos", granted_at: ~U[2026-10-01 00:00:00Z], withdrawn_at: nil}
      withdrawn = %{granted | withdrawn_at: ~U[2026-10-02 00:00:00Z]}

      assert :ok = ConsentPolicy.require_photos([granted])
      assert {:error, :body_photo_consent_required} = ConsentPolicy.require_photos([withdrawn])
      assert {:error, :body_photo_consent_required} = ConsentPolicy.require_photos([])

      assert [
               %{scope: "body_photos", active: false, withdrawn_at: %DateTime{}},
               %{scope: "health_data", active: false}
             ] =
               ConsentPolicy.summary([withdrawn])
    end

    test "a coach sees photos only on coach_full with consent" do
      assert ConsentPolicy.photos_visible_to_coach?("coach_full", true)
      refute ConsentPolicy.photos_visible_to_coach?("coach_full", false)
      refute ConsentPolicy.photos_visible_to_coach?("coach_numbers", true)
    end
  end

  describe "settings" do
    @now ~U[2026-10-20 09:00:00Z]

    test "defaults and partial changes" do
      current = SettingsPolicy.effective(nil)
      assert current.units == "metric" and current.weight_display == "number"

      assert {:ok, %{weight_display: "trend", journal_sections: sections}} =
               SettingsPolicy.changes(
                 current,
                 %{"weight_display" => "trend", "journal_sections" => %{"cravings" => false}},
                 @now
               )

      assert sections == %{"body" => true, "wellness" => true, "cravings" => false}

      assert {:error, :invalid_body_settings, %{field: "units"}} =
               SettingsPolicy.changes(current, %{units: "stone"}, @now)

      assert {:error, :invalid_body_settings, %{field: "measure_reminder_weeks"}} =
               SettingsPolicy.changes(current, %{measure_reminder_weeks: 13}, @now)

      assert {:error, :invalid_body_settings, %{field: "journal_sections"}} =
               SettingsPolicy.changes(current, %{journal_sections: %{"food" => true}}, @now)
    end

    test "the reminder counts from the latest of turning it on, last snapshot and last reminder" do
      {:ok, changes} =
        SettingsPolicy.changes(SettingsPolicy.effective(nil), %{measure_reminder_weeks: 2}, @now)

      settings = Map.merge(SettingsPolicy.effective(nil), changes)

      assert changes.reminder_anchor_at == @now
      refute SettingsPolicy.reminder_due?(settings, nil, DateTime.add(@now, 13 * 86_400))
      assert SettingsPolicy.reminder_due?(settings, nil, DateTime.add(@now, 14 * 86_400))

      later_snapshot = DateTime.add(@now, 10 * 86_400)

      refute SettingsPolicy.reminder_due?(
               settings,
               later_snapshot,
               DateTime.add(@now, 14 * 86_400)
             )

      refute SettingsPolicy.reminder_due?(SettingsPolicy.effective(nil), nil, @now)

      assert {:ok, %{measure_reminder_weeks: nil, reminder_anchor_at: nil}} =
               SettingsPolicy.changes(settings, %{"measure_reminder_weeks" => nil}, @now)

      assert SettingsPolicy.reminder_dedupe_key("u", ~D[2026-10-20]) ==
               "body_measure_reminder:u:2026-10-20"
    end
  end

  test "cursor round trip" do
    id = Ecto.UUID.generate()
    cursor = SnapshotCursor.encode(%{taken_at: ~U[2026-10-01 08:00:00.000000Z], id: id})
    assert {:ok, %{id: ^id}} = SnapshotCursor.decode(cursor)
    assert {:error, :invalid_cursor} = SnapshotCursor.decode("nope")
    assert SnapshotCursor.limit("500") == 100
  end
end
