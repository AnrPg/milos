defmodule MilosTraining.Appointments.SlotModeTest do
  @moduledoc "ADR-170: a session is in person or online; only an online one carries an https link."
  use ExUnit.Case, async: true

  alias MilosTraining.Appointments.Slot

  @base %{
    organization_id: Ecto.UUID.generate(),
    coach_id: Ecto.UUID.generate(),
    kind: "pt_session",
    format: "one_to_one",
    starts_at: ~U[2026-11-20 08:00:00.000000Z],
    duration_minutes: 60
  }

  test "in person by default, online with an https link" do
    assert %{valid?: true, changes: changes} = Slot.create_changeset(@base)
    refute Map.has_key?(changes, :meeting_url)

    assert %{valid?: true} =
             Slot.create_changeset(
               Map.merge(@base, %{mode: "online", meeting_url: "https://meet.example.org/abc"})
             )

    assert %{valid?: true} = Slot.create_changeset(Map.put(@base, :mode, "online"))
  end

  test "refuses a link that is not https, a link in person and an unknown mode" do
    refute Slot.create_changeset(
             Map.merge(@base, %{mode: "online", meeting_url: "http://meet.example.org"})
           ).valid?

    refute Slot.create_changeset(
             Map.merge(@base, %{mode: "online", meeting_url: "javascript:alert(1)"})
           ).valid?

    refute Slot.create_changeset(Map.put(@base, :meeting_url, "https://meet.example.org")).valid?
    refute Slot.create_changeset(Map.put(@base, :mode, "park")).valid?
  end
end
