defmodule Palee.Application.ChangeInjuryTest do
  @moduledoc "ADR-140 §3: injury updates and reopenings as timestamped timeline events."

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{ChangeInjury, ListMyInjuries, MarkMyInjuryHealed, ReportInjury}
  alias Palee.Identity.UserContext

  setup do
    member = user_fixture()
    other = user_fixture()
    ctx = UserContext.new(member)

    {:ok, injury} =
      ReportInjury.call(ctx, member.id, %{
        "body_area" => "knee",
        "severity" => "moderate",
        "training_limitations" => "No jumping"
      })

    %{member: member, other: other, ctx: ctx, injury: injury}
  end

  test "an update records text and only the fields that changed", %{
    ctx: ctx,
    member: member,
    injury: injury
  } do
    assert {:ok, updated} =
             ChangeInjury.update_mine(ctx, member.id, injury.id, %{
               "note" => "  Better after physio  ",
               "severity" => "mild",
               "training_limitations" => "No jumping"
             })

    assert updated.severity == "mild"

    assert [%{event_type: "reported"}, %{event_type: "updated", payload: payload}] =
             updated.events

    assert payload == %{
             "note" => "Better after physio",
             "changes" => [%{"field" => "severity", "from" => "moderate", "to" => "mild"}]
           }

    assert {:ok, text_only} =
             ChangeInjury.update_mine(ctx, member.id, injury.id, %{"note" => "Still a bit sore"})

    assert %{payload: %{"changes" => [], "note" => "Still a bit sore"}} =
             List.last(text_only.events)
  end

  test "an update with neither text nor a change is refused", %{
    ctx: ctx,
    member: member,
    injury: injury
  } do
    assert {:error, :empty_update} =
             ChangeInjury.update_mine(ctx, member.id, injury.id, %{
               "severity" => "moderate",
               "note" => " "
             })
  end

  test "another member cannot update or reopen the injury", %{other: other, injury: injury} do
    other_ctx = UserContext.new(other)

    assert {:error, :not_found} =
             ChangeInjury.update_mine(other_ctx, other.id, injury.id, %{"note" => "x"})

    assert {:error, :not_found} = ChangeInjury.reopen_mine(other_ctx, other.id, injury.id)
  end

  test "healed then reopened shows the whole progression in order", %{
    ctx: ctx,
    member: member,
    injury: injury
  } do
    assert {:error, :injury_already_active} = ChangeInjury.reopen_mine(ctx, member.id, injury.id)
    {:ok, _healed} = MarkMyInjuryHealed.call(ctx, member.id, injury.id, %{})
    assert {:ok, reopened} = ChangeInjury.reopen_mine(ctx, member.id, injury.id)

    assert reopened.status == "active"
    assert is_nil(reopened.healed_on)

    assert {:ok, %{injuries: [listed]}} = ListMyInjuries.call(ctx, member.id)
    assert Enum.map(listed.events, & &1.event_type) == ~w(reported marked_healed reopened)
  end
end
