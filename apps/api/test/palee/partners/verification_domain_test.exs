defmodule Palee.Partners.Domain.VerificationDomainTest do
  @moduledoc "ADR-280 §2: the pure rules of Partners verification."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Palee.Partners.Domain.{
    Eligibility,
    PhoneCodePolicy,
    SponsorPolicy,
    VerificationReviewPolicy
  }

  @now ~U[2027-03-25 10:00:00.000000Z]
  @me "00000000-0000-0000-0000-00000000000a"
  @other "00000000-0000-0000-0000-00000000000b"

  defp member(overrides \\ %{}),
    do:
      Map.merge(
        %{method: "membership", status: "verified", penalty_until: nil, vouches: 0},
        overrides
      )

  defp request(overrides \\ %{}) do
    Map.merge(
      %{
        status: "collecting",
        consent_at: @now,
        phone_verified_at: nil,
        selfie_uploaded_at: nil
      },
      overrides
    )
  end

  describe "Eligibility" do
    test "a verification decides, whatever the request" do
      assert %{status: :verified, method: "membership", next_step: nil} =
               Eligibility.status(%{status: "verified", method: "membership"}, request(), 0)

      assert %{status: :suspended} =
               Eligibility.status(%{status: "suspended", method: "sponsors"}, nil, 0)
    end

    test "the sponsor path's next step, in order" do
      assert %{status: :needs_verification, next_step: :consent} = Eligibility.status(nil, nil, 0)

      assert %{next_step: :consent} = Eligibility.status(nil, request(%{consent_at: nil}), 0)
      assert %{next_step: :sponsors} = Eligibility.status(nil, request(), 1)
      assert %{next_step: :phone} = Eligibility.status(nil, request(), 2)

      assert %{next_step: :selfie} =
               Eligibility.status(nil, request(%{phone_verified_at: @now}), 2)

      assert %{status: :in_review, next_step: nil} =
               Eligibility.status(nil, request(%{status: "in_review"}), 2)

      assert %{status: :rejected, next_step: :consent} =
               Eligibility.status(nil, request(%{status: "rejected"}), 2)

      assert %{status: :needs_verification, next_step: :consent} =
               Eligibility.status(nil, request(%{status: "withdrawn"}), 0)
    end

    test "require_verified" do
      assert :ok = Eligibility.require_verified(%{status: "verified"})
      assert {:error, :partner_suspended} = Eligibility.require_verified(%{status: "suspended"})
      assert {:error, :partner_verification_required} = Eligibility.require_verified(nil)
    end

    test "who may apply" do
      assert {:error, :partner_already_verified} =
               Eligibility.check_can_apply(%{status: "verified"}, nil)

      assert {:error, :partner_suspended} =
               Eligibility.check_can_apply(%{status: "suspended"}, nil)

      assert {:error, :partner_verification_in_review} =
               Eligibility.check_can_apply(nil, request(%{status: "in_review"}))

      assert :ok = Eligibility.check_can_apply(nil, request())
    end
  end

  describe "SponsorPolicy" do
    test "only a member, not suspended, not blocked, not oneself" do
      assert :ok = SponsorPolicy.check(member(), @other, @me, false, @now)

      assert {:error, :partner_sponsor_not_eligible} =
               SponsorPolicy.check(member(%{method: "sponsors"}), @other, @me, false, @now)

      assert {:error, :partner_sponsor_not_eligible} =
               SponsorPolicy.check(member(%{status: "suspended"}), @other, @me, false, @now)

      assert {:error, :partner_sponsor_not_eligible} =
               SponsorPolicy.check(nil, @other, @me, false, @now)

      assert {:error, :partner_sponsor_not_eligible} =
               SponsorPolicy.check(member(), @other, @me, true, @now)

      assert {:error, :partner_sponsor_not_eligible} =
               SponsorPolicy.check(member(), @me, @me, false, @now)
    end

    test "5 vouches in the rolling 30 days" do
      assert :ok = SponsorPolicy.check(member(%{vouches: 4}), @other, @me, false, @now)

      assert {:error, :partner_sponsor_quota} =
               SponsorPolicy.check(member(%{vouches: 5}), @other, @me, false, @now)

      assert SponsorPolicy.quota_window_start(@now) == ~U[2027-02-23 10:00:00.000000Z]
    end

    test "a 60-day pause after a suspension" do
      until = SponsorPolicy.penalty_until(@now)
      assert DateTime.diff(until, @now, :day) == 60

      assert {:error, :partner_sponsor_penalty} =
               SponsorPolicy.check(member(%{penalty_until: until}), @other, @me, false, @now)

      assert :ok =
               SponsorPolicy.check(member(%{penalty_until: @now}), @other, @me, false, @now)

      assert SponsorPolicy.extend_penalty(until, @now) == until
      assert SponsorPolicy.extend_penalty(nil, until) == until
    end

    test "answering, asking again, cancelling" do
      assert {:ok, %{status: "vouched", decided_at: @now}} =
               SponsorPolicy.answer(%{status: "requested"}, "vouch", @now)

      assert {:ok, %{status: "declined"}} =
               SponsorPolicy.answer(%{status: "requested"}, "decline", @now)

      assert {:error, :partner_vouch_request_closed} =
               SponsorPolicy.answer(%{status: "vouched"}, "decline", @now)

      assert :insert = SponsorPolicy.ask(nil, @now)
      assert {:update, %{status: "requested"}} = SponsorPolicy.ask(%{status: "cancelled"}, @now)
      assert {:keep, _} = SponsorPolicy.ask(%{status: "vouched"}, @now)
      assert {:error, :partner_sponsor_declined} = SponsorPolicy.ask(%{status: "declined"}, @now)
      assert {:ok, %{status: "cancelled"}} = SponsorPolicy.cancel(%{status: "requested"})
      assert {:error, :not_found} = SponsorPolicy.cancel(%{status: "vouched"})
      assert {:error, :invalid_partner_vouch_decision} = SponsorPolicy.normalize_decision("yes")
    end

    test "links are single use and live 10 minutes" do
      expires_at = SponsorPolicy.link_expires_at(@now)
      assert DateTime.diff(expires_at, @now) == 600
      link = %{candidate_id: @me, expires_at: expires_at, used_at: nil}

      assert :ok = SponsorPolicy.check_link(link, @other, @now)

      assert {:error, :partner_link_expired} =
               SponsorPolicy.check_link(link, @other, expires_at)

      assert {:error, :partner_link_expired} =
               SponsorPolicy.check_link(%{link | used_at: @now}, @other, @now)

      assert {:error, :partner_sponsor_not_eligible} = SponsorPolicy.check_link(link, @me, @now)
      assert {:error, :partner_link_expired} = SponsorPolicy.check_link(nil, @other, @now)
      assert {:error, :partner_link_expired} = SponsorPolicy.normalize_token("bad token!")
      assert byte_size(SponsorPolicy.link_digest("abc")) == 32
    end

    property "the quota never goes below zero and is reached at exactly 5" do
      check all(vouches <- integer(0..50)) do
        left = SponsorPolicy.quota_left(vouches)
        assert left >= 0 and left <= 5
        result = SponsorPolicy.check(member(%{vouches: vouches}), @other, @me, false, @now)
        assert result == if(vouches < 5, do: :ok, else: {:error, :partner_sponsor_quota})
      end
    end
  end

  describe "PhoneCodePolicy" do
    test "E.164 normalisation" do
      assert {:ok, "+306912345678"} = PhoneCodePolicy.normalize("691 234 5678")
      assert {:ok, "+306912345678"} = PhoneCodePolicy.normalize("+30 691-234-5678")
      assert {:ok, "+306912345678"} = PhoneCodePolicy.normalize("00306912345678")
      assert {:ok, "+447911123456"} = PhoneCodePolicy.normalize("+44 7911 123456")
      assert {:error, :partner_phone_invalid} = PhoneCodePolicy.normalize("2101234567")
      assert {:error, :partner_phone_invalid} = PhoneCodePolicy.normalize("+302101234567")
      assert {:error, :partner_phone_invalid} = PhoneCodePolicy.normalize("+0123")
      assert {:error, :partner_phone_invalid} = PhoneCodePolicy.normalize(nil)
    end

    test "masking keeps the country code and the last 3 digits" do
      assert PhoneCodePolicy.mask("+306912345678") == "+30 •••••••678"
      assert PhoneCodePolicy.mask(nil) == nil
    end

    test "codes: 6 digits, 10 minutes, 5 attempts" do
      assert PhoneCodePolicy.code_from(42) == "000042"
      assert {:ok, "123456"} = PhoneCodePolicy.normalize_code("123 456")
      assert {:error, :partner_code_invalid} = PhoneCodePolicy.normalize_code("12345")

      code = %{attempts: 0, consumed_at: nil, expires_at: PhoneCodePolicy.expires_at(@now)}
      assert :ok = PhoneCodePolicy.check_code(code, @now)

      assert {:error, :partner_code_expired} =
               PhoneCodePolicy.check_code(code, DateTime.add(@now, 600))

      assert {:error, :partner_code_expired} =
               PhoneCodePolicy.check_code(%{code | attempts: 5}, @now)

      assert {:error, :partner_code_expired} =
               PhoneCodePolicy.check_code(%{code | consumed_at: @now}, @now)

      assert {:error, :partner_code_invalid} = PhoneCodePolicy.check_code(nil, @now)
    end

    test "send limits: 3 an hour, 10 a day" do
      assert :ok = PhoneCodePolicy.check_send_rate(2, 9)
      assert {:error, :partner_phone_rate_limited} = PhoneCodePolicy.check_send_rate(3, 3)
      assert {:error, :partner_phone_rate_limited} = PhoneCodePolicy.check_send_rate(0, 10)
    end

    property "codes are always 6 digits and the SMS carries them" do
      check all(random <- integer(0..4_294_967_295)) do
        code = PhoneCodePolicy.code_from(random)
        assert code =~ ~r/^[0-9]{6}$/
        assert {:ok, ^code} = PhoneCodePolicy.normalize_code(code)
        assert PhoneCodePolicy.sms_body(code) =~ code
      end
    end

    property "a normalised number is E.164 and normalising is idempotent" do
      check all(national <- string(?0..?9, length: 8)) do
        {:ok, e164} = PhoneCodePolicy.normalize("69" <> national)
        assert e164 =~ ~r/^\+[1-9][0-9]{7,14}$/
        assert {:ok, ^e164} = PhoneCodePolicy.normalize(e164)
        refute PhoneCodePolicy.mask(e164) =~ national
      end
    end
  end

  describe "VerificationReviewPolicy" do
    test "the selfie: types, key, magic bytes, 8 MB" do
      assert {:ok, %{extension: ".heic"}} = VerificationReviewPolicy.validate_upload("image/heic")

      assert {:error, {:invalid_fields, _}} =
               VerificationReviewPolicy.validate_upload("application/pdf")

      key = VerificationReviewPolicy.selfie_key(@me, @other, ".jpg")
      assert key == "users/#{@me}/partner-verification/#{@other}.jpg"
      assert VerificationReviewPolicy.selfie_content_type(key, @me, @other) == "image/jpeg"
      assert VerificationReviewPolicy.selfie_content_type(key, @other, @other) == nil

      jpeg = <<0xFF, 0xD8, 0xFF, 0xE0>>
      heic = <<0, 0, 0, 24, "ftypheic", 0, 0>>
      assert :ok = VerificationReviewPolicy.validate_file("image/jpeg", jpeg, 1000)
      assert :ok = VerificationReviewPolicy.validate_file("image/heic", heic, 1000)

      assert {:error, :partner_selfie_invalid} =
               VerificationReviewPolicy.validate_file("image/png", jpeg, 1000)

      assert {:error, :partner_selfie_invalid} =
               VerificationReviewPolicy.validate_file("image/jpeg", jpeg, 8 * 1024 * 1024 + 1)
    end

    test "submittable with consent, 2 vouches and a verified phone" do
      ready = request(%{phone_verified_at: @now})
      assert :ok = VerificationReviewPolicy.check_submittable(ready, 2)

      assert {:error, :partner_verification_incomplete} =
               VerificationReviewPolicy.check_submittable(ready, 1)

      assert VerificationReviewPolicy.missing(request(%{consent_at: nil}), 0) ==
               [:consent, :sponsors, :phone]
    end

    test "decisions: reject needs a reason, the selfie and phone go" do
      assert {:ok, %{decision: "approve", reason: nil}} =
               VerificationReviewPolicy.normalize_decision(%{"decision" => "approve"})

      assert {:error, :partner_decision_reason_required} =
               VerificationReviewPolicy.normalize_decision(%{decision: "reject", reason: " "})

      assert {:error, :invalid_partner_verification_decision} =
               VerificationReviewPolicy.normalize_decision(%{decision: "maybe"})

      changes = VerificationReviewPolicy.decision_changes("reject", "blurry", @other, @now)
      assert %{status: "rejected", selfie_key: nil, phone_ciphertext: nil} = changes
      refute Map.has_key?(changes, :phone_hash)

      assert {:error, :partner_verification_closed} =
               VerificationReviewPolicy.check_decidable(%{status: "approved"})
    end

    test "a selfie unreviewed for 7 days expires" do
      fresh = request(%{status: "in_review", selfie_uploaded_at: DateTime.add(@now, -6, :day)})
      stale = request(%{status: "in_review", selfie_uploaded_at: DateTime.add(@now, -7, :day)})
      refute VerificationReviewPolicy.selfie_expired?(fresh, @now)
      assert VerificationReviewPolicy.selfie_expired?(stale, @now)
      refute VerificationReviewPolicy.selfie_expired?(%{stale | status: "collecting"}, @now)
      assert %{status: "expired", selfie_key: nil} = VerificationReviewPolicy.expire_changes()
    end

    property "selfie codes are 4 digits" do
      check all(random <- integer(0..4_294_967_295)) do
        assert VerificationReviewPolicy.selfie_code_from(random) =~ ~r/^[0-9]{4}$/
      end
    end
  end
end
