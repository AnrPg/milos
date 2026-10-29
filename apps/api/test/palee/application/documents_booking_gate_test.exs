defmodule Palee.Application.DocumentsBookingGateTest do
  @moduledoc """
  ADR-252: the booking flow refuses a client with an unsigned mandatory
  document (`documents_required` with the list), lets them book once they
  sign, applies to waitlists too, and never stops staff placing a client.
  """
  use Palee.DataCase, async: false

  alias Palee.Application.{JoinClassWaitlist, PlaceMemberInClass, SubmitBooking}
  alias Palee.Application.Documents.{DocumentsAdmin, MyDocuments}
  alias Palee.Organizations
  alias Palee.TestFixtures

  setup do
    start_supervised!({Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)})

    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Documents Gym #{System.unique_integer([:positive])}"})

    owner_context = join_gym(organization, owner, :owner)
    client = TestFixtures.user_fixture()
    client_context = join_gym(organization, client, :member)

    %{
      organization: organization,
      owner: owner,
      owner_context: owner_context,
      client: client,
      client_context: client_context
    }
  end

  defp join_gym(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end

  defp slot(owner, owner_context, attrs \\ %{}) do
    class_type = TestFixtures.class_type_fixture(%{tenant_context: owner_context})
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: owner_context})

    TestFixtures.slot_fixture(
      workout,
      Map.merge(%{tenant_context: owner_context, class_type_id: class_type.id}, attrs)
    )
  end

  defp mandatory_waiver(owner_context) do
    {:ok, %{template: template, version: version}} =
      DocumentsAdmin.create_template(owner_context, %{
        kind: "waiver",
        title: "Απαλλαγή ευθύνης",
        requirement: "mandatory",
        body: "Κείμενο"
      })

    {template, version}
  end

  test "an unsigned mandatory document blocks booking until it is signed", ctx do
    %{owner: owner, owner_context: owner_context, client: client, client_context: client_context} =
      ctx

    slot = slot(owner, owner_context)
    {template, version} = mandatory_waiver(owner_context)

    assert {:error, :documents_required, %{documents: [document], health_certificate: nil}} =
             SubmitBooking.call(client_context, client, slot.id)

    assert document.template_id == template.id
    assert document.reason == "unsigned"

    assert {:ok, _} =
             MyDocuments.sign(
               client_context,
               template.id,
               %{version_id: version.id, agreed: true, typed_name: "Μαρία Παπαδοπούλου"},
               %{ip_address: {127, 0, 0, 1}, user_agent: "test", account: nil}
             )

    assert {:ok, booking} = SubmitBooking.call(client_context, client, slot.id)
    assert booking.user_id == client.id
  end

  test "optional documents and staff never block", ctx do
    %{owner: owner, owner_context: owner_context, client: client} = ctx
    slot = slot(owner, owner_context)

    {:ok, _} =
      DocumentsAdmin.create_template(owner_context, %{
        kind: "privacy",
        title: "Newsletter",
        requirement: "optional",
        body: "Κείμενο"
      })

    {_template, _version} = mandatory_waiver(owner_context)

    # Staff placing the client bypass the gate.
    assert {:ok, %{booking: booking}} =
             PlaceMemberInClass.call(owner_context, client.id, %{"slot_id" => slot.id})

    assert booking.user_id == client.id

    # Staff booking themselves are not clients.
    coach = TestFixtures.user_fixture()
    coach_context = join_gym(ctx.organization, coach, :coach)
    assert {:ok, _booking} = SubmitBooking.call(coach_context, coach, slot.id)
  end

  test "the gate is on by default and staff can turn it off", ctx do
    %{owner: owner, owner_context: owner_context, client: client, client_context: client_context} =
      ctx

    slot = slot(owner, owner_context)
    mandatory_waiver(owner_context)

    assert {:error, :documents_required, _} = SubmitBooking.call(client_context, client, slot.id)

    {:ok, _} = DocumentsAdmin.save_settings(owner_context, %{block_booking_on_unsigned: false})
    assert {:ok, _booking} = SubmitBooking.call(client_context, client, slot.id)
  end

  test "joining a waitlist is gated too", ctx do
    %{owner: owner, owner_context: owner_context, client: client, client_context: client_context} =
      ctx

    slot = slot(owner, owner_context, %{capacity: 1, auto_approve: true})
    other = TestFixtures.user_fixture()
    other_context = join_gym(ctx.organization, other, :member)
    assert {:ok, _booking} = SubmitBooking.call(other_context, other, slot.id)

    mandatory_waiver(owner_context)

    assert {:error, :documents_required, %{documents: [_]}} =
             JoinClassWaitlist.call(client_context, client, slot.id)
  end
end
