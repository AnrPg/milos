defmodule Palee.FiscalTest do
  @moduledoc """
  ADR-240–242 end to end through the Fiscal context and the database: legal
  identity, gapless numbering, idempotent issue, credit notes, insert-only
  rows, the signed hash chain, period closings and the audit archive. Runs
  with Row Level Security enforced.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]

  alias Palee.{Fiscal, Repo}

  @now ~U[2027-02-01 10:00:00.000000Z]

  @identity %{
    legal_name: "CrossFit Αθήνα ΙΚΕ",
    country_code: "GR",
    tax_id: "090000045",
    tax_office: "Α' Αθηνών",
    street: "Ερμού",
    building_number: "10",
    postal_code: "10563",
    city: "Αθήνα"
  }

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    %{organization: organization, owner: owner, context: context}
  end

  defp ready(%{context: context, owner: owner}) do
    {:ok, %{complete: true}} = Fiscal.save_identity(context, @identity, owner.id, @now)
    :ok
  end

  defp request(key, extra \\ %{}) do
    Map.merge(
      %{
        kind: "receipt",
        issue_date: ~D[2027-02-01],
        idempotency_key: key,
        payment_method: "card",
        lines: [
          %{description: "Μηνιαία συνδρομή", quantity: 1, unit_price_cents: 6000},
          %{description: "Drop-in", quantity: 2, unit_price_cents: 1500}
        ]
      },
      extra
    )
  end

  describe "legal identity" do
    test "reports missing fields, saves partially and journals the change", %{
      context: context,
      owner: owner
    } do
      assert %{identity: nil, complete: false} = Fiscal.identity_status(context)

      assert {:ok, %{complete: false, missing: missing}} =
               Fiscal.save_identity(
                 context,
                 %{country_code: "GR", legal_name: "Box"},
                 owner.id,
                 @now
               )

      assert :tax_id in missing and :tax_office in missing

      assert {:error, {:invalid_fields, %{tax_id: :check_digit}}} =
               Fiscal.save_identity(context, %{tax_id: "090000046"}, owner.id, @now)

      assert {:ok, %{complete: true, identity: identity}} =
               Fiscal.save_identity(context, @identity, owner.id, @now)

      assert identity.currency == "EUR"
      assert {:ok, %{valid: true, entries: 2}} = Fiscal.verify_journal(context, owner.id, @now)
    end
  end

  describe "documents" do
    setup :ready

    test "a receipt is numbered, hashed and journaled; retries replay it", %{
      context: context,
      owner: owner
    } do
      assert {:ok, doc, :issued} = Fiscal.issue(context, request("k-1"), owner.id, @now)
      assert doc.number == "R-000001"
      assert doc.gross_cents == 9000
      assert length(doc.lines) == 2
      assert doc.content_hash =~ ~r/^[0-9a-f]{64}$/

      assert {:ok, same, :replayed} = Fiscal.issue(context, request("k-1"), owner.id, @now)
      assert same.id == doc.id

      assert {:error, :idempotency_key_reused} =
               Fiscal.issue(context, request("k-1", %{payment_method: "cash"}), owner.id, @now)

      assert {:ok, %{number: "R-000002"}, :issued} =
               Fiscal.issue(context, request("k-2"), owner.id, @now)
    end

    test "a failed issue does not use up a number", %{context: context, owner: owner} do
      bad = request("bad", %{lines: [%{description: "x", quantity: 0, unit_price_cents: 1}]})
      assert {:error, :invalid_quantity} = Fiscal.issue(context, bad, owner.id, @now)

      assert {:ok, %{number: "R-000001"}, :issued} =
               Fiscal.issue(context, request("ok"), owner.id, @now)
    end

    test "documents and lines refuse UPDATE and DELETE", %{context: context, owner: owner} do
      {:ok, doc, :issued} = Fiscal.issue(context, request("k"), owner.id, @now)
      {:ok, id} = Ecto.UUID.dump(doc.id)

      bypass_rls(fn ->
        for sql <- [
              "UPDATE fiscal_documents SET gross_cents = 1 WHERE id = $1",
              "DELETE FROM fiscal_documents WHERE id = $1",
              "DELETE FROM fiscal_document_lines WHERE document_id = $1"
            ] do
          assert_raise Postgrex.Error, ~r/insert-only/, fn -> Repo.query!(sql, [id]) end
        end
      end)
    end

    test "credit notes correct documents and never exceed them", %{context: context, owner: owner} do
      {:ok, doc, :issued} = Fiscal.issue(context, request("k"), owner.id, @now)

      assert {:ok, partial, :issued} =
               Fiscal.credit(
                 context,
                 doc.id,
                 [%{position: 2, quantity: 1}],
                 ~D[2027-02-02],
                 "c-1",
                 owner.id,
                 @now
               )

      assert partial.number == "C-000001"
      assert partial.corrects_document_id == doc.id
      assert partial.gross_cents == 1500

      assert {:ok, rest, :issued} =
               Fiscal.credit(context, doc.id, :all, ~D[2027-02-02], "c-2", owner.id, @now)

      assert rest.gross_cents == 7500

      assert {:error, :already_credited} =
               Fiscal.credit(context, doc.id, :all, ~D[2027-02-02], "c-3", owner.id, @now)

      assert [_, _] = Fiscal.credit_notes(context, doc.id)
    end

    test "a credit note keeps its reason in the document, its hash and the journal (ADR-265)",
         %{context: context, owner: owner} do
      {:ok, doc, :issued} = Fiscal.issue(context, request("k"), owner.id, @now)

      assert {:error, :invalid_credit_reason} =
               Fiscal.credit(context, doc.id, :all, ~D[2027-02-02], "c-1", owner.id, @now,
                 reason: "whim"
               )

      assert {:ok, preview} =
               Fiscal.credit_preview(context, doc.id, [%{position: 2, quantity: 2}], ~D[2027-02-02])

      assert preview.gross_cents == 3000

      assert {:ok, note, :issued} =
               Fiscal.credit(
                 context,
                 doc.id,
                 [%{position: 2, quantity: 2}],
                 ~D[2027-02-02],
                 "c-1",
                 owner.id,
                 @now,
                 reason: "product_return"
               )

      assert note.credit_reason == "product_return"
      assert note.gross_cents == preview.gross_cents
      stored = Fiscal.get_document(context, note.id)
      assert stored.credit_reason == "product_return"

      # The reason is hashed: the same content without it hashes differently.
      assert Fiscal.document_hash(stored, stored.lines) == stored.content_hash

      refute Fiscal.document_hash(%{stored | credit_reason: nil}, stored.lines) ==
               stored.content_hash

      # Without a reason the hash is the one documents had before ADR-265.
      assert Fiscal.document_hash(%{stored | credit_reason: nil}, stored.lines) ==
               Fiscal.document_hash(Map.delete(stored, :credit_reason), stored.lines)

      [entry] =
        context
        |> Fiscal.FiscalStore.list_journal_entries(%{})
        |> Enum.filter(&(&1.subject_id == note.id))

      assert entry.payload["credit_reason"] == "product_return"
      assert {:ok, %{valid: true}} = Fiscal.verify_journal(context, owner.id, @now)
    end

    test "another gym never sees the documents", %{context: context, owner: owner} do
      {:ok, doc, :issued} = Fiscal.issue(context, request("k"), owner.id, @now)
      {_org, _owner, other} = bypass_rls(fn -> organization_fixture() end)

      assert Fiscal.get_document(other, doc.id) == nil
      assert %{total: 0} = Fiscal.list_documents(other)
      assert %{total: 1} = Fiscal.list_documents(context)
    end
  end

  describe "journal, closings and archive" do
    setup :ready

    test "verification catches a tampered entry", %{context: context, owner: owner} do
      {:ok, _doc, :issued} = Fiscal.issue(context, request("k"), owner.id, @now)
      assert {:ok, %{valid: true}} = Fiscal.verify_journal(context, owner.id, @now)

      bypass_rls(fn ->
        Repo.query!(
          "ALTER TABLE fiscal_journal_entries DISABLE TRIGGER fiscal_journal_entries_immutable"
        )

        Repo.query!(
          "UPDATE fiscal_journal_entries SET payload = jsonb_set(payload, '{gross_cents}', '1') WHERE event_type = 'document_issued'"
        )

        Repo.query!(
          "ALTER TABLE fiscal_journal_entries ENABLE TRIGGER fiscal_journal_entries_immutable"
        )
      end)

      assert {:ok, %{valid: false, broken_at: 2, reason: :hash_mismatch}} =
               Fiscal.verify_journal(context, owner.id, @now)
    end

    test "ended days, months and years close once with carried grand totals", %{
      context: context,
      owner: owner
    } do
      {:ok, _doc, :issued} =
        Fiscal.issue(context, request("a", %{issue_date: ~D[2027-01-31]}), owner.id, @now)

      {:ok, _doc, :issued} =
        Fiscal.issue(context, request("b", %{issue_date: ~D[2027-02-01]}), owner.id, @now)

      assert {:ok, closings} = Fiscal.close_due_periods(context, ~D[2027-02-02], @now)

      assert Enum.map(closings, &{&1.period_kind, &1.period_start}) == [
               {"day", ~D[2027-01-31]},
               {"day", ~D[2027-02-01]},
               {"month", ~D[2027-01-01]}
             ]

      [_jan31, feb1, _month] = closings
      assert feb1.totals["EUR"]["gross_cents"] == 9000
      assert feb1.totals["EUR"]["grand_total_cents"] == 18_000

      assert {:ok, []} = Fiscal.close_due_periods(context, ~D[2027-02-02], @now)
      assert {:ok, %{valid: true}} = Fiscal.verify_journal(context, owner.id, @now)
    end

    test "the archive holds every file, a manifest with hashes and its signature", %{
      context: context,
      owner: owner
    } do
      {:ok, _doc, :issued} = Fiscal.issue(context, request("k"), owner.id, @now)

      assert {:ok, %{filename: filename, content: zip}} =
               Fiscal.archive(context, ~D[2027-02-01], ~D[2027-02-28], owner.id, @now)

      assert filename == "palee-fiscal-2027-02-01-2027-02-28.zip"
      {:ok, files} = :zip.unzip(zip, [:memory])
      files = Map.new(files, fn {name, content} -> {to_string(name), content} end)

      manifest = Jason.decode!(files["manifest.json"])

      for %{"name" => name, "sha256" => sha} <- manifest["files"] do
        assert :crypto.hash(:sha256, files[name]) |> Base.encode16(case: :lower) == sha
      end

      %{"signature" => signature, "key_id" => key_id} = Jason.decode!(files["manifest.sig"])
      assert Fiscal.signer().verify(files["manifest.json"], signature, key_id)
      assert files["documents.jsonl"] |> String.split("\n", trim: true) |> length() == 1
    end

    test "issuing is refused without a signing key", %{context: context, owner: owner} do
      config = Application.get_env(:palee, Palee.Infrastructure.Fiscal.Ed25519JournalSigner)
      Application.put_env(:palee, Palee.Infrastructure.Fiscal.Ed25519JournalSigner, [])

      on_exit(fn ->
        Application.put_env(:palee, Palee.Infrastructure.Fiscal.Ed25519JournalSigner, config)
      end)

      assert {:error, :journal_signing_unavailable} =
               Fiscal.issue(context, request("k"), owner.id, @now)
    end
  end

  test "purge removes every fiscal row of the gym", %{context: context, owner: owner} = tags do
    ready(tags)
    {:ok, _doc, :issued} = Fiscal.issue(context, request("k"), owner.id, @now)

    assert {:ok, deleted} = Fiscal.purge_tenant_data(context)
    assert deleted["fiscal_documents"] == 1
    assert %{identity: nil} = Fiscal.identity_status(context)
  end
end
