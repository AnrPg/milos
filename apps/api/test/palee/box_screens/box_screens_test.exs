defmodule Palee.BoxScreensTest do
  @moduledoc """
  ADR-253 against the database with Row Level Security enforced: screens are
  the box's own rows, a pairing code is found outside any tenant only by its
  hash and pairs one device once, and overrides record who changed them.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]

  alias Palee.{BoxScreens, Repo}

  @now ~U[2027-02-09 10:00:00.000000Z]

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    {other_organization, _other_owner, other_context} = bypass_rls(fn -> organization_fixture() end)

    %{
      organization: organization,
      owner: owner,
      context: context,
      other_organization: other_organization,
      other_context: other_context
    }
  end

  test "a screen is created with a code whose hash alone is stored", ctx do
    assert {:ok, screen, %{code: code, expires_at: expires_at}} =
             BoxScreens.create(ctx.context, %{name: " Αίθουσα 1 "}, ctx.owner.id, @now)

    assert screen.name == "Αίθουσα 1"
    assert screen.organization_id == ctx.organization.id
    assert screen.token_version == 0
    assert DateTime.compare(expires_at, ~U[2027-02-09 10:15:00Z]) == :eq
    assert screen.pairing_code_hash == :crypto.hash(:sha256, String.replace(code, "-", ""))

    %{rows: [[stored]]} =
      bypass_rls(fn ->
        Repo.query!("SELECT count(*) FROM box_screens WHERE pairing_code_hash::text LIKE $1", [
          "%#{code}%"
        ])
      end)

    assert stored == 0
  end

  test "screens are invisible to other boxes", ctx do
    {:ok, screen, _code} = BoxScreens.create(ctx.context, %{name: "TV"}, ctx.owner.id, @now)

    assert [%{id: id}] = BoxScreens.list(ctx.context)
    assert id == screen.id
    assert [] == BoxScreens.list(ctx.other_context)
    assert nil == BoxScreens.get(ctx.other_context, screen.id)

    assert {:error, :box_screen_not_found} =
             BoxScreens.update(ctx.other_context, screen.id, %{name: "Mine"})

    assert {:error, :not_found} = BoxScreens.delete(ctx.other_context, screen.id)
    assert %{name: "TV"} = BoxScreens.get(ctx.context, screen.id)
  end

  test "a code pairs one device once, in the box's scope", ctx do
    {:ok, screen, %{code: code}} =
      BoxScreens.create(ctx.context, %{name: "TV"}, ctx.owner.id, @now)

    typed = code |> String.downcase() |> String.replace("-", " ")

    assert {:ok, organization_id, screen_id, hash} = BoxScreens.find_pairing(typed, @now)
    assert {organization_id, screen_id} == {ctx.organization.id, screen.id}

    # The claim is checked again in the tenant scope: not from another box.
    assert {:error, :invalid_pairing_code} =
             BoxScreens.claim(ctx.other_context, screen_id, hash, @now)

    assert {:ok, paired} = BoxScreens.claim(ctx.context, screen_id, hash, @now)
    assert paired.token_version == 1
    assert paired.paired_at == @now
    assert is_nil(paired.pairing_code_hash)

    assert {:error, :invalid_pairing_code} = BoxScreens.claim(ctx.context, screen_id, hash, @now)
    assert {:error, :invalid_pairing_code} = BoxScreens.find_pairing(code, @now)
  end

  test "a code stops working after 15 minutes; a new one moves the screen", ctx do
    {:ok, screen, %{code: code}} =
      BoxScreens.create(ctx.context, %{name: "TV"}, ctx.owner.id, @now)

    assert {:error, :invalid_pairing_code} =
             BoxScreens.find_pairing(code, DateTime.add(@now, 15 * 60, :second))

    later = DateTime.add(@now, 3600, :second)
    assert {:ok, _screen, %{code: second}} = BoxScreens.new_pairing_code(ctx.context, screen.id, later)
    assert {:error, :invalid_pairing_code} = BoxScreens.find_pairing(code, later)
    assert {:ok, _org, _id, hash} = BoxScreens.find_pairing(second, later)
    assert {:ok, %{token_version: 1}} = BoxScreens.claim(ctx.context, screen.id, hash, later)

    assert {:ok, _screen, %{code: third}} = BoxScreens.new_pairing_code(ctx.context, screen.id, later)
    assert {:ok, _org, _id, hash} = BoxScreens.find_pairing(third, later)
    assert {:ok, %{token_version: 2}} = BoxScreens.claim(ctx.context, screen.id, hash, later)
  end

  test "a box has at most 20 screens and each needs a name", ctx do
    for n <- 1..20 do
      assert {:ok, _screen, _code} =
               BoxScreens.create(ctx.context, %{name: "TV #{n}"}, ctx.owner.id, @now)
    end

    assert {:error, :too_many_screens} =
             BoxScreens.create(ctx.context, %{name: "TV 21"}, ctx.owner.id, @now)

    assert {:ok, _screen, _code} =
             BoxScreens.create(ctx.other_context, %{name: "TV"}, ctx.owner.id, @now)

    assert {:error, :invalid_screen_name} =
             BoxScreens.create(ctx.other_context, %{name: " "}, ctx.owner.id, @now)
  end

  test "an override records who changed it; automatic again records it too", ctx do
    {:ok, screen, _code} = BoxScreens.create(ctx.context, %{name: "TV"}, ctx.owner.id, @now)
    slot_id = Ecto.UUID.generate()

    assert {:ok, pinned} =
             BoxScreens.set_override(
               ctx.context,
               screen.id,
               %{view: "class", slot_id: slot_id, until: DateTime.add(@now, 1800, :second)},
               [slot_id],
               ctx.owner.id,
               @now
             )

    assert %{override_view: "class", override_slot_id: ^slot_id} = pinned
    assert pinned.focus_changed_by_id == ctx.owner.id
    assert %{view: "class", slot_id: ^slot_id} = BoxScreens.active_override(pinned, @now)

    assert {:error, :invalid_screen_override} =
             BoxScreens.set_override(ctx.context, screen.id, %{view: "class"}, [], ctx.owner.id, @now)

    later = DateTime.add(@now, 60, :second)
    assert {:ok, auto} = BoxScreens.clear_override(ctx.context, screen.id, ctx.owner.id, later)
    assert is_nil(auto.override_view) and is_nil(auto.override_slot_id)
    assert auto.focus_changed_at == later
  end

  test "removing a screen deletes its row", ctx do
    {:ok, screen, _code} = BoxScreens.create(ctx.context, %{name: "TV"}, ctx.owner.id, @now)
    assert :ok = BoxScreens.delete(ctx.context, screen.id)
    assert nil == BoxScreens.get(ctx.context, screen.id)
    assert {:error, :not_found} = BoxScreens.delete(ctx.context, screen.id)
  end
end
