defmodule Palee.Fiscal.Domain.TillSigningDomainTest do
  @moduledoc "ADR-250/251 pure rules: TSE and RKSV payloads, the two outbox policies."

  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.{EInvoicePolicy, RksvReceipt, TillSigningPolicy, TseTransaction}

  @now ~U[2027-02-08 10:00:00.000000Z]

  defp document(kind, breakdown, gross, method \\ "cash") do
    %{
      kind: kind,
      tax_breakdown: breakdown,
      gross_cents: gross,
      payment_method: method,
      currency: "EUR"
    }
  end

  describe "TseTransaction" do
    test "sums gross amounts per DSFinV-K rate in the standard order" do
      doc =
        document(
          "receipt",
          [
            %{rate_bp: 700, gross_cents: 300},
            %{"rate_bp" => 1900, "gross_cents" => 5_950},
            %{rate_bp: 700, gross_cents: 107}
          ],
          6_357,
          "card"
        )

      assert {:ok, %{"standard_v1" => %{"receipt" => receipt}}} = TseTransaction.schema(doc)
      assert receipt["receipt_type"] == "RECEIPT"

      assert receipt["amounts_per_vat_rate"] == [
               %{"vat_rate" => "NORMAL", "amount" => "59.50"},
               %{"vat_rate" => "REDUCED_1", "amount" => "4.07"}
             ]

      assert receipt["amounts_per_payment_type"] == [
               %{"payment_type" => "NON_CASH", "amount" => "63.57", "currency_code" => "EUR"}
             ]
    end

    test "a credit note is negative; an unknown rate is refused" do
      assert {:ok, schema} =
               TseTransaction.schema(
                 document("credit_note", [%{rate_bp: 1900, gross_cents: 1_190}], 1_190)
               )

      assert [%{"amount" => "-11.90"}] = schema["standard_v1"]["receipt"]["amounts_per_vat_rate"]

      assert {:error, :unsupported_vat_rate} =
               TseTransaction.schema(
                 document("receipt", [%{rate_bp: 2000, gross_cents: 100}], 100)
               )
    end

    test "decimal and print lines" do
      assert TseTransaction.decimal(5) == "0.05"
      assert TseTransaction.decimal(-1_234) == "-12.34"
      assert TseTransaction.print_lines(%{status: "pending"}) == [{"TSE", "Signatur ausstehend"}]

      assert [{"TSE", "TSE ausgefallen"}, {"Ausfall seit", "2027-02-08T10:00:00Z"}] =
               TseTransaction.print_lines(%{status: "device_failed", failed_at: @now})
    end
  end

  describe "RksvReceipt" do
    test "uses fiskaly AT's rate groups (20/10/13/0/19 %)" do
      doc =
        document(
          "receipt",
          [
            %{rate_bp: 1900, gross_cents: 119},
            %{rate_bp: 1000, gross_cents: 110},
            %{rate_bp: 2000, gross_cents: 120},
            %{rate_bp: 1300, gross_cents: 113},
            %{rate_bp: 0, gross_cents: 100}
          ],
          562
        )

      assert {:ok, schema} = RksvReceipt.schema(doc)

      assert Enum.map(schema["standard_v1"]["receipt"]["amounts_per_vat_rate"], & &1["vat_rate"]) ==
               ["STANDARD", "REDUCED_1", "REDUCED_2", "ZERO", "SPECIAL"]

      assert {:error, :unsupported_vat_rate} =
               RksvReceipt.schema(document("receipt", [%{rate_bp: 700, gross_cents: 1}], 1))
    end

    test "parses the machine-readable code and recognises an outage" do
      code =
        "_R1-AT1_KASSE-1_83469_2027-02-08T11:00:05_60,00_0,00_0,00_0,00_0,00_dGVzdA==_5c8e5_cHJldg==_"

      assert {:ok,
              %{receipt_number: "83469", amounts: %{"STANDARD" => "60,00"}, device_failed: false}} =
               RksvReceipt.parse_code(code <> "c2ln")

      assert {:ok, %{device_failed: true}} =
               RksvReceipt.parse_code(code <> RksvReceipt.failed_signature())

      assert RksvReceipt.failed_signature() == Base.encode64("Sicherheitseinrichtung ausgefallen")
      assert {:error, :invalid_code} = RksvReceipt.parse_code("nope")

      lines =
        RksvReceipt.print_lines(%{
          status: "signed",
          qr_code_data: code <> RksvReceipt.failed_signature(),
          register_serial: "KASSE-1",
          receipt_number: "83469"
        })

      assert {"Hinweis", "Sicherheitseinrichtung ausgefallen"} in lines

      assert RksvReceipt.print_lines(%{qr_code_data: nil}) == [
               {"Hinweis", RksvReceipt.failed_marker()}
             ]
    end

    test "a null receipt is all zero" do
      assert [%{"amount" => "0.00"}] =
               RksvReceipt.null_schema()["standard_v1"]["receipt"]["amounts_per_vat_rate"]
    end
  end

  describe "TillSigningPolicy" do
    @row %{device: "tse", kind: "receipt", status: "sending", attempts: 1}

    test "which documents are signed" do
      de = %{till_device: :tse}
      assert TillSigningPolicy.device(de) == "tse"
      assert TillSigningPolicy.device(%{}) == nil
      assert TillSigningPolicy.required?(de, %{kind: "receipt"})
      refute TillSigningPolicy.required?(de, %{kind: "invoice"})
      assert TillSigningPolicy.required?(de, %{kind: "credit_note"}, "receipt")
      refute TillSigningPolicy.required?(de, %{kind: "credit_note"}, "invoice")
      refute TillSigningPolicy.required?(%{}, %{kind: "receipt"})
    end

    test "invoices paid at the till and their credit notes are signed, in DE and AT" do
      for profile <- [%{till_device: :tse}, %{till_device: :rksv}] do
        for method <- ["cash", "card"] do
          invoice = %{kind: "invoice", payment_method: method}
          assert TillSigningPolicy.required?(profile, invoice)
          assert TillSigningPolicy.required?(profile, %{invoice | kind: "credit_note"}, invoice)
        end

        for method <- ["bank_transfer", "online", "other", nil] do
          invoice = %{kind: "invoice", payment_method: method}
          refute TillSigningPolicy.required?(profile, invoice)
          refute TillSigningPolicy.required?(profile, %{invoice | kind: "credit_note"}, invoice)
        end

        receipt = %{kind: "receipt", payment_method: "online"}
        assert TillSigningPolicy.required?(profile, %{kind: "credit_note"}, receipt)
      end

      refute TillSigningPolicy.required?(%{till_device: :none}, %{
               kind: "invoice",
               payment_method: "cash"
             })
    end

    test "France (SIGN FR) signs receipts and their credit notes only" do
      fr = %{till_device: :sign_fr}
      invoice = %{kind: "invoice", payment_method: "cash"}
      assert TillSigningPolicy.device(fr) == "sign_fr"
      assert TillSigningPolicy.required?(fr, %{kind: "receipt"})
      assert TillSigningPolicy.required?(fr, %{kind: "credit_note"}, "receipt")
      assert TillSigningPolicy.required?(fr, %{kind: "credit_note"}, %{kind: "receipt"})
      refute TillSigningPolicy.required?(fr, invoice)
      refute TillSigningPolicy.required?(fr, %{invoice | kind: "credit_note"}, invoice)
    end

    test "uncertain is read back, late German receipts fail, the rest is signed" do
      assert TillSigningPolicy.operation(%{@row | status: "uncertain"}, @now, nil) == :lookup
      assert TillSigningPolicy.operation(@row, @now, DateTime.add(@now, -299)) == :sign
      assert TillSigningPolicy.operation(@row, @now, DateTime.add(@now, -300)) == :fail

      assert TillSigningPolicy.operation(
               %{@row | device: "rksv"},
               @now,
               DateTime.add(@now, -9_999)
             ) == :sign
    end

    test "outcomes" do
      assert %{status: "signed", signature_value: "x", signed_at: @now} =
               TillSigningPolicy.outcome(
                 @row,
                 {:ok, %{signature_value: "x", hint: "ignored"}},
                 @now
               )

      assert %{status: "device_failed", failed_at: @now, last_error_message: "SCU down"} =
               TillSigningPolicy.outcome(
                 @row,
                 {:ok, %{device_failed: true, hint: "SCU down"}},
                 @now
               )

      assert %{status: "uncertain", next_attempt_at: next} =
               TillSigningPolicy.outcome(@row, {:error, {:uncertain, :timeout}}, @now)

      assert DateTime.compare(next, @now) == :gt

      assert %{status: "pending", attempts: 0} =
               TillSigningPolicy.outcome(
                 %{@row | status: "uncertain"},
                 {:error, :not_found},
                 @now
               )

      assert %{status: "rejected", last_error_code: "E_X"} =
               TillSigningPolicy.outcome(
                 @row,
                 {:error, {:rejected, [%{code: "E_X", message: "m"}]}},
                 @now
               )

      assert %{status: "pending", last_error_code: "transient"} =
               TillSigningPolicy.outcome(@row, {:error, {:transient, :closed}}, @now,
                 issued_at: DateTime.add(@now, -10)
               )

      assert %{status: "device_failed"} =
               TillSigningPolicy.outcome(@row, {:error, {:transient, :closed}}, @now,
                 issued_at: DateTime.add(@now, -400)
               )

      assert %{status: "failed"} =
               TillSigningPolicy.outcome(
                 %{@row | attempts: TillSigningPolicy.max_attempts(), device: "rksv"},
                 {:error, {:transient, :closed}},
                 @now
               )
    end

    test "staff retry reads an uncertain row back first" do
      assert %{status: "uncertain"} = TillSigningPolicy.retry(%{status: "uncertain"}, @now)

      assert %{status: "pending", failed_at: nil} =
               TillSigningPolicy.retry(%{status: "failed"}, @now)

      assert TillSigningPolicy.attempt_outcome({:ok, %{device_failed: true}}) == "device_failed"
      assert TillSigningPolicy.attempt_outcome({:error, :not_found}) == "not_found"
    end
  end

  describe "EInvoicePolicy" do
    @submission %{status: "sending", attempts: 1, polls: 0}

    test "submit outcomes; an uncertain submit is never resent by itself" do
      assert %{status: "submitted", provider_submission_id: "g", next_attempt_at: %DateTime{}} =
               EInvoicePolicy.submit_outcome(@submission, {:ok, %{submission_id: "g"}}, @now)

      assert %{status: "uncertain", next_attempt_at: nil} =
               EInvoicePolicy.submit_outcome(@submission, {:error, {:uncertain, :timeout}}, @now)

      assert %{status: "rejected"} =
               EInvoicePolicy.submit_outcome(
                 @submission,
                 {:error, {:rejected, [%{code: "1", message: "m"}]}},
                 @now
               )

      assert %{status: "pending", attempts: 0, last_error_code: "connection_invalid"} =
               EInvoicePolicy.submit_outcome(@submission, {:error, {:unauthorized, :bad}}, @now)

      assert %{status: "failed"} =
               EInvoicePolicy.submit_outcome(
                 %{@submission | attempts: EInvoicePolicy.max_attempts()},
                 {:error, {:transient, :closed}},
                 @now
               )
    end

    test "polls end delivered, rejected or unconfirmed" do
      submitted = %{@submission | status: "submitted"}

      assert %{status: "delivered"} =
               EInvoicePolicy.poll_outcome(submitted, {:ok, :delivered}, @now)

      assert %{status: "rejected", last_error_code: "delivery_failed"} =
               EInvoicePolicy.poll_outcome(
                 submitted,
                 {:ok, {:failed, [%{code: "x", message: "y"}]}},
                 @now
               )

      assert %{status: "submitted", polls: 1} =
               EInvoicePolicy.poll_outcome(submitted, {:ok, :in_progress}, @now)

      last =
        Stream.iterate(0, &(&1 + 1))
        |> Enum.find(&is_nil(EInvoicePolicy.next_poll_at(&1, @now)))

      assert %{status: "failed", last_error_code: "delivery_unconfirmed"} =
               EInvoicePolicy.poll_outcome(
                 %{submitted | polls: last - 1},
                 {:ok, :in_progress},
                 @now
               )
    end

    test "a staff retry keeps the GUID of an uncertain submission only" do
      refute Map.has_key?(EInvoicePolicy.retry(%{status: "uncertain"}, @now), :idempotency_guid)
      assert %{idempotency_guid: guid} = EInvoicePolicy.retry(%{status: "rejected"}, @now)
      assert {:ok, _} = Ecto.UUID.cast(guid)
    end
  end
end
