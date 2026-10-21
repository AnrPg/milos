defmodule Palee.Finance.RefundReceiptsTest do
  @moduledoc """
  ADR-126 refund receipts: issued atomically with payment reversals, gapless
  per-tenant numbering (sequential and under transaction rollback),
  idempotent replays, immutability, member/staff visibility and two-tenant
  isolation - all under the RLS-enforcing runtime role.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  alias Palee.Application.{
    GetFinanceRefundReceipt,
    ListFinanceRefundReceipts,
    RenderFinanceRefundReceipt,
    ReverseFinancePayment
  }

  alias Palee.Finance
  alias Palee.Finance.Domain.DocumentNumber
  alias Palee.Finance.FinanceRefundReceipt
  alias Palee.Organizations
  alias Palee.TestFixtures

  defp tenant(name) do
    bypass_rls(fn ->
      owner = TestFixtures.admin_fixture()
      member = TestFixtures.user_fixture(%{role: :member})

      {:ok, organization} =
        Organizations.create_organization(%{
          name: "#{name} #{System.unique_integer([:positive])}"
        })

      for {user, role} <- [{owner, :owner}, {member, :member}] do
        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
      {:ok, member_context} = Organizations.resolve_tenant_context(member, organization.slug)

      %{
        organization: organization,
        owner: owner,
        member: member,
        context: context,
        member_context: member_context
      }
    end)
  end

  defp paid_payment(%{context: context, member: member}, amount_cents, status \\ "paid") do
    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, payment} =
      Finance.record_payment(context, membership.id, %{
        amount_cents: amount_cents,
        payment_method: "card_manual",
        payment_status: status,
        paid_on: Date.utc_today()
      })

    payment
  end

  defp reverse(tenant, payment, amount_cents, request_id \\ Ecto.UUID.generate()) do
    Finance.with_tenant_context(tenant.context, fn ->
      ReverseFinancePayment.call(tenant.context, tenant.member.id, payment.id, tenant.owner.id, %{
        "amount_cents" => amount_cents,
        "reason" => "Class cancelled",
        "request_id" => request_id
      })
    end)
  end

  test "a refund issues an immutable, numbered receipt with a self-contained snapshot" do
    tenant = tenant("Receipt Gym")
    payment = paid_payment(tenant, 5_000)

    assert {:ok, reversal} = reverse(tenant, payment, 2_000)
    receipt = reversal.refund_receipt

    assert receipt.receipt_number == "RFD-000001"
    assert receipt.sequence == 1
    assert receipt.finance_payment_reversal_id == reversal.id
    assert receipt.membership_payment_id == payment.id
    assert receipt.amount_cents == 2_000
    assert receipt.reason == "Class cancelled"
    assert receipt.issued_by_id == tenant.owner.id
    assert receipt.integrity_verified

    assert receipt.snapshot["organization"]["name"] == tenant.organization.name

    assert receipt.snapshot["member"]["display_name"] ==
             tenant.member.nickname

    assert receipt.snapshot["totals"]["remaining_paid_cents"] == 3_000

    assert {:ok, second} = reverse(tenant, payment, 1_000)
    assert second.refund_receipt.receipt_number == "RFD-000002"
    assert second.refund_receipt.snapshot["totals"]["previously_refunded_cents"] == 2_000

    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Finance.with_tenant_context(tenant.context, fn ->
        Repo.update_all(
          from(r in FinanceRefundReceipt, where: r.id == ^receipt.id),
          set: [amount_cents: 1]
        )
      end)
    end
  end

  test "a replayed reversal returns the same receipt without consuming a number" do
    tenant = tenant("Replay Gym")
    payment = paid_payment(tenant, 4_000)
    request_id = Ecto.UUID.generate()

    assert {:ok, first} = reverse(tenant, payment, 1_000, request_id)
    assert {:ok, replay} = reverse(tenant, payment, 1_000, request_id)
    assert replay.id == first.id
    assert replay.refund_receipt.id == first.refund_receipt.id

    assert {:ok, next} = reverse(tenant, payment, 500)
    assert next.refund_receipt.receipt_number == "RFD-000002"
  end

  test "waiver reversals move no money and get no receipt" do
    tenant = tenant("Waiver Gym")
    payment = paid_payment(tenant, 3_000, "waived")

    assert {:ok, reversal} = reverse(tenant, payment, 3_000)
    assert reversal.reversal_type == "waiver_reversal"
    assert reversal.refund_receipt == nil

    assert {:ok, %{refund_receipts: []}} =
             ListFinanceRefundReceipts.call(tenant.context, :staff, %{})
  end

  test "numbering is gapless across sequential reversals and per tenant" do
    first = tenant("Sequence Gym A")
    second = tenant("Sequence Gym B")
    payment_a = paid_payment(first, 10_000)
    payment_b = paid_payment(second, 10_000)

    for _ <- 1..5, do: {:ok, _} = reverse(first, payment_a, 100)
    assert {:ok, other} = reverse(second, payment_b, 100)

    {:ok, %{refund_receipts: receipts}} =
      ListFinanceRefundReceipts.call(first.context, :staff, %{})

    assert DocumentNumber.gapless?(Enum.map(receipts, & &1.sequence))
    assert Enum.map(receipts, & &1.receipt_number) |> Enum.sort() |> List.last() == "RFD-000005"
    assert other.refund_receipt.receipt_number == "RFD-000001"
  end

  test "a rolled-back reversal releases its number (counter row is transactional)" do
    tenant = tenant("Rollback Gym")
    payment = paid_payment(tenant, 6_000)

    assert {:error, :rolled_back} =
             Repo.transaction(fn ->
               {:ok, reversal} = reverse(tenant, payment, 1_000)
               assert reversal.refund_receipt.receipt_number == "RFD-000001"
               Repo.rollback(:rolled_back)
             end)

    assert {:ok, reversal} = reverse(tenant, payment, 1_000)
    assert reversal.refund_receipt.receipt_number == "RFD-000001"
  end

  test "members see only their own receipts; other tenants see none" do
    tenant = tenant("Visibility Gym")
    other = tenant("Visibility Gym Other")
    payment = paid_payment(tenant, 5_000)
    {:ok, reversal} = reverse(tenant, payment, 2_500)
    receipt_id = reversal.refund_receipt.id

    assert {:ok, %{refund_receipts: [%{id: ^receipt_id} = listed]}} =
             ListFinanceRefundReceipts.call(
               tenant.member_context,
               {:member, tenant.member.id},
               %{}
             )

    refute Map.has_key?(listed, :snapshot)

    assert {:ok, %{id: ^receipt_id}} =
             GetFinanceRefundReceipt.call(
               tenant.member_context,
               receipt_id,
               {:member, tenant.member.id}
             )

    stranger = TestFixtures.user_fixture(%{role: :member})

    assert {:error, :not_found} =
             GetFinanceRefundReceipt.call(tenant.context, receipt_id, {:member, stranger.id})

    assert {:error, :not_found} = GetFinanceRefundReceipt.call(other.context, receipt_id, :staff)

    assert {:ok, %{refund_receipts: []}} =
             ListFinanceRefundReceipts.call(other.context, :staff, %{})

    assert {:ok, %{refund_receipts: [_]}} =
             ListFinanceRefundReceipts.call(tenant.context, :staff, %{"q" => "RFD-0000"})

    assert {:ok, %{refund_receipts: []}} =
             ListFinanceRefundReceipts.call(tenant.context, :staff, %{"q" => "nothing"})
  end

  test "the printable document is localized and deterministic" do
    tenant = tenant("Document Gym")
    payment = paid_payment(tenant, 5_000)
    {:ok, reversal} = reverse(tenant, payment, 2_000)
    id = reversal.refund_receipt.id

    assert {:ok, %{html: html, receipt_number: "RFD-000001"}} =
             RenderFinanceRefundReceipt.call(tenant.context, id, :staff, "el")

    assert {:ok, %{html: ^html}} =
             RenderFinanceRefundReceipt.call(tenant.context, id, :staff, "el")

    assert html =~ "Απόδειξη επιστροφής χρημάτων"
    assert html =~ "20.00 EUR"

    assert {:ok, %{html: arabic}} =
             RenderFinanceRefundReceipt.call(tenant.context, id, :staff, "ar")

    assert arabic =~ "dir=\"rtl\""
  end
end
