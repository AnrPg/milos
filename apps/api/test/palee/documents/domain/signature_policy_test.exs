defmodule Palee.Documents.Domain.SignaturePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Documents.Domain.{MemberDocuments, SignaturePolicy}

  @version %{id: "11111111-1111-4111-8111-111111111111"}

  defp params(extra),
    do:
      Map.merge(%{version_id: @version.id, agreed: true, typed_name: "Μαρία Παπαδοπούλου"}, extra)

  describe "what the signer sends" do
    test "a typed name, a drawn signature or both, after agreeing to the text" do
      assert {:ok, %{typed_name: "Μαρία Παπαδοπούλου", drawn_signature: nil}} =
               SignaturePolicy.validate(
                 params(%{typed_name: "  Μαρία   Παπαδοπούλου "}),
                 @version
               )

      drawn = %{"width" => 300, "height" => 100, "strokes" => [[[1.4, 2.6], [10, 20]], [[5, 5]]]}

      assert {:ok, %{typed_name: nil, drawn_signature: signature}} =
               SignaturePolicy.validate(
                 params(%{typed_name: nil, drawn_signature: drawn}),
                 @version
               )

      assert signature == %{width: 300, height: 100, strokes: [[[1, 3], [10, 20]], [[5, 5]]]}
    end

    test "agreeing is required and something must be signed" do
      assert {:error, {:invalid_fields, %{agreed: "required"}}} =
               SignaturePolicy.validate(params(%{agreed: false}), @version)

      assert {:error, {:invalid_fields, %{typed_name: "signature_required"}}} =
               SignaturePolicy.validate(params(%{typed_name: " "}), @version)

      assert {:error, {:invalid_fields, %{typed_name: "too_short"}}} =
               SignaturePolicy.validate(params(%{typed_name: "Μ"}), @version)
    end

    test "drawn strokes stay inside their box and within limits" do
      outside = %{width: 100, height: 50, strokes: [[[0, 0], [101, 10]]]}
      too_many = %{width: 100, height: 50, strokes: List.duplicate([[1, 1]], 101)}
      no_strokes = %{width: 100, height: 50, strokes: []}

      for drawn <- [outside, too_many, no_strokes, "png"] do
        assert {:error, {:invalid_fields, %{drawn_signature: "invalid"}}} =
                 SignaturePolicy.validate(params(%{drawn_signature: drawn}), @version)
      end
    end

    test "signing a version other than the current one is refused" do
      assert {:error, :document_version_outdated} =
               SignaturePolicy.validate(
                 params(%{version_id: "22222222-2222-4222-8222-222222222222"}),
                 @version
               )

      assert {:error, :document_not_published} = SignaturePolicy.validate(params(%{}), nil)
    end
  end

  describe "evidence" do
    test "the evidence names the text, the moment, the device and the account, and is hashed" do
      attrs = %{
        signature_id: "33333333-3333-4333-8333-333333333333",
        organization_id: "44444444-4444-4444-8444-444444444444",
        template_id: "55555555-5555-4555-8555-555555555555",
        version_id: @version.id,
        version_number: 2,
        content_hash: String.duplicate("a", 64),
        signed_at: ~U[2027-02-08 10:00:00Z],
        level: "simple",
        provider: "palee",
        signer: %{
          user_id: "66666666-6666-4666-8666-666666666666",
          display_name: "Μαρία",
          email: "m@example.com"
        },
        typed_name: "Μαρία",
        drawn_signature: nil,
        ip_address: SignaturePolicy.ip_address({203, 0, 113, 7}),
        user_agent: String.duplicate("x", 600)
      }

      {evidence, hash} = SignaturePolicy.evidence(attrs)

      assert evidence.ip_address == "203.0.113.7"
      assert String.length(evidence.user_agent) == 512
      assert evidence.signed_at.microsecond == {0, 6}
      assert evidence.content_hash == attrs.content_hash
      assert hash =~ ~r/^[0-9a-f]{64}$/
      assert {_evidence, ^hash} = SignaturePolicy.evidence(attrs)

      {_evidence, other} = SignaturePolicy.evidence(%{attrs | ip_address: "198.51.100.1"})
      refute other == hash
      assert SignaturePolicy.ip_address({0, 0, 0, 0, 0, 0, 0, 1}) == "::1"
    end
  end

  describe "status and the booking gate" do
    @template %{
      id: "t1",
      title: "Όροι",
      kind: "terms",
      requirement: "mandatory",
      status: "active",
      current_version_number: 3,
      required_version_number: 2
    }

    test "a signature counts from the latest major version on" do
      assert SignaturePolicy.status(@template, nil) == :unsigned
      assert SignaturePolicy.status(@template, %{version_number: 1}) == :resign_required
      assert SignaturePolicy.status(@template, %{version_number: 2}) == :signed
      assert SignaturePolicy.status(@template, %{version_number: 3}) == :signed
    end

    test "only mandatory documents are outstanding; optional ones are offered" do
      optional = %{@template | id: "t2", title: "Newsletter", requirement: "optional"}
      draft = %{@template | id: "t3", current_version_number: 0, required_version_number: 0}
      archived = %{@template | id: "t4", status: "archived"}

      items =
        MemberDocuments.items([optional, @template, draft, archived], %{}, ["t2"])

      assert Enum.map(items, & &1.template.id) == ["t1", "t2"]

      assert [%{outstanding: true, status: :unsigned}, %{outstanding: false, requested: true}] =
               items

      assert [%{template: %{id: "t1"}}] = MemberDocuments.outstanding(items)
    end

    test "the gate lists blocking documents and a missing or expired certificate" do
      settings = %{
        block_booking_on_unsigned: true,
        block_booking_on_health_certificate: false,
        health_certificate_required: false
      }

      items = MemberDocuments.items([@template], %{"t1" => %{version_number: 1}}, [])

      assert {:error, :documents_required,
              %{
                documents: [%{template_id: "t1", reason: "resign_required", kind: "terms"}],
                health_certificate: nil
              }} = MemberDocuments.booking_gate(settings, items, "missing")

      assert :ok =
               MemberDocuments.booking_gate(
                 %{settings | block_booking_on_unsigned: false},
                 items,
                 "missing"
               )

      health = %{
        settings
        | block_booking_on_unsigned: false,
          block_booking_on_health_certificate: true
      }

      assert {:error, :documents_required, %{documents: [], health_certificate: "expired"}} =
               MemberDocuments.booking_gate(health, items, "expired")

      assert :ok = MemberDocuments.booking_gate(health, items, "expiring")

      assert MemberDocuments.health_outstanding(%{health_certificate_required: true}, "missing") ==
               "missing"

      assert MemberDocuments.health_outstanding(%{health_certificate_required: false}, "missing") ==
               nil
    end
  end
end
