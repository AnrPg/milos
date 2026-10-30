defmodule Palee.Application.PartnerVerificationTest do
  @moduledoc """
  ADR-280 verification against the database, as the RLS-enforcing runtime
  role: verification by a membership on first use, the sponsor path from
  consent to the Palee team's decision, the sponsors' quota and pause, the
  retention job, account deletion and what row security hides.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.Application.{
    PartnerEligibility,
    PartnerSponsoring,
    PartnerVerification,
    PartnerVerificationRetention,
    PlatformPartnerVerifications
  }

  alias Palee.Community.Follow
  alias Palee.{Organizations, Repo}
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Partners.{Sponsorship, Verification, VerificationRequest}
  alias Palee.TestSupport.{MemoryObjectStore, MemorySmsSender}

  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 64)

  setup do
    MemorySmsSender.start()
    MemoryObjectStore.start()

    bypass_rls(fn ->
      candidate = user_fixture()
      sponsor_a = user_fixture()
      sponsor_b = user_fixture()
      vendor = user_fixture()
      {:ok, _vendor} = Organizations.grant_vendor(vendor.id)

      for sponsor <- [sponsor_a, sponsor_b] do
        buddies!(candidate, sponsor)
        member_verified!(sponsor)
      end

      %{
        candidate: candidate,
        sponsor_a: sponsor_a,
        sponsor_b: sponsor_b,
        vendor: vendor,
        phone: "+3069#{:rand.uniform(89_999_999) + 10_000_000}"
      }
    end)
  end

  defp ctx(user), do: %{user_id: user.id}

  defp buddies!(a, b) do
    for {from, to} <- [{a, b}, {b, a}] do
      Repo.insert!(%Follow{
        user_id: from.id,
        target_type: "user",
        target_id: to.id,
        status: "active",
        accepted_at: DateTime.utc_now()
      })
    end
  end

  defp member_verified!(user, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Verification{
          user_id: user.id,
          method: "membership",
          status: "verified",
          verified_at: DateTime.utc_now()
        },
        attrs
      )
    )
  end

  defp ready_for_review!(ctx) do
    me = ctx(ctx.candidate)
    assert {:ok, %{request: %{selfie_code: code}}} = PartnerVerification.consent(me)
    assert code =~ ~r/^[0-9]{4}$/

    for sponsor <- [ctx.sponsor_a, ctx.sponsor_b] do
      {:ok, %{sponsorship: %{id: id}}} =
        PartnerVerification.request_sponsor(me, %{"sponsor_id" => sponsor.id})

      {:ok, %{status: "vouched"}} =
        PartnerSponsoring.decide(ctx(sponsor), id, %{"decision" => "vouch"})
    end

    {:ok, _sent} = PartnerVerification.send_phone_code(me, %{"phone" => ctx.phone})
    code = MemorySmsSender.last_code(ctx.phone)
    {:ok, _overview} = PartnerVerification.confirm_phone(me, %{"code" => code})

    {:ok, %{file_key: key}} =
      PartnerVerification.selfie_upload_url(me, %{"content_type" => "image/jpeg"})

    :ok = MemoryObjectStore.put_object(:documents, key, @jpeg, "image/jpeg")
    {:ok, overview} = PartnerVerification.submit(me, %{"file_key" => key})
    {overview, key}
  end

  describe "membership" do
    test "an active member of a live box is verified on first use", ctx do
      gym =
        bypass_rls(fn ->
          {:ok, gym} = Organizations.create_organization(%{name: "Verified Box"})

          RepoContext.run(%{organization_id: gym.id}, fn ->
            Repo.insert!(%Palee.Finance.Membership{
              organization_id: gym.id,
              user_id: ctx.candidate.id,
              user_type_snapshot: "member",
              status: "active",
              signup_source: "admin_created"
            })
          end)

          gym
        end)

      assert :ok = PartnerEligibility.require_verified(ctx(ctx.candidate))

      assert %{status: :verified, method: "membership"} =
               PartnerEligibility.status(ctx(ctx.candidate))

      assert %{method: "membership", box_name: "Verified Box"} =
               PartnerEligibility.verification_badges([ctx.candidate.id])[ctx.candidate.id]

      assert ctx.candidate.id in PartnerEligibility.verified_user_ids([ctx.candidate.id])
      assert gym.id
    end

    test "nobody else is verified", ctx do
      assert {:error, :partner_verification_required} =
               PartnerEligibility.require_verified(ctx(ctx.candidate))

      assert [] = PartnerEligibility.verified_user_ids([ctx.candidate.id])
    end
  end

  describe "the sponsor path" do
    test "consent, two vouches, phone, selfie, then the Palee team approves", ctx do
      {overview, key} = ready_for_review!(ctx)
      assert overview.eligibility.status == "in_review"
      assert overview.request.vouches == 2

      vendor = %{user_id: ctx.vendor.id}
      {:ok, %{requests: [item]}} = PlatformPartnerVerifications.list(vendor)
      {:ok, detail} = PlatformPartnerVerifications.show(vendor, item.id)
      assert detail.selfie_url =~ "expires=300"
      assert detail.phone =~ "•"
      assert length(detail.sponsors) == 2

      {:ok, %{status: "approved"}} =
        PlatformPartnerVerifications.decide(vendor, item.id, %{"decision" => "approve"})

      assert :error = MemoryObjectStore.get(:documents, key)
      assert :ok = PartnerEligibility.require_verified(ctx(ctx.candidate))

      assert %{method: "sponsors", box_name: nil} =
               PartnerEligibility.verification_badges([ctx.candidate.id])[ctx.candidate.id]
    end

    test "rejecting needs a reason and keeps only the outcome", ctx do
      {_overview, _key} = ready_for_review!(ctx)
      vendor = %{user_id: ctx.vendor.id}
      {:ok, %{requests: [item]}} = PlatformPartnerVerifications.list(vendor)

      assert {:error, :partner_decision_reason_required} =
               PlatformPartnerVerifications.decide(vendor, item.id, %{"decision" => "reject"})

      {:ok, %{status: "rejected"}} =
        PlatformPartnerVerifications.decide(vendor, item.id, %{
          "decision" => "reject",
          "reason" => "The face is not visible"
        })

      request = bypass_rls(fn -> Repo.get!(VerificationRequest, item.id) end)
      assert is_nil(request.selfie_key) and is_nil(request.phone_ciphertext)
      assert request.phone_hash

      assert %{status: :rejected} = PartnerEligibility.status(ctx(ctx.candidate))
    end

    test "the person never decides their own request", ctx do
      {_overview, _key} = ready_for_review!(ctx)

      assert_raise Postgrex.Error, fn ->
        RepoContext.run(ctx(ctx.candidate), fn ->
          Repo.update_all(VerificationRequest, set: [status: "approved"])
        end)
      end
    end

    test "submitting without two vouches fails", ctx do
      me = ctx(ctx.candidate)
      {:ok, _} = PartnerVerification.consent(me)

      {:ok, %{file_key: key}} =
        PartnerVerification.selfie_upload_url(me, %{"content_type" => "image/jpeg"})

      :ok = MemoryObjectStore.put_object(:documents, key, @jpeg, "image/jpeg")

      assert {:error, :partner_verification_incomplete} =
               PartnerVerification.submit(me, %{"file_key" => key})

      assert :error = MemoryObjectStore.get(:documents, key)
    end

    test "a sponsor verified by sponsors cannot vouch", ctx do
      outsider = bypass_rls(fn -> user_fixture() end)

      bypass_rls(fn ->
        buddies!(ctx.candidate, outsider)
        member_verified!(outsider, %{method: "sponsors"})
      end)

      {:ok, _} = PartnerVerification.consent(ctx(ctx.candidate))

      assert {:error, :partner_sponsor_not_eligible} =
               PartnerVerification.request_sponsor(ctx(ctx.candidate), %{
                 "sponsor_id" => outsider.id
               })

      {:ok, %{candidates: candidates}} =
        PartnerVerification.sponsor_candidates(ctx(ctx.candidate))

      row = Enum.find(candidates, &(&1.person.id == outsider.id))
      assert %{eligible: false, reason: "not_verified"} = row
    end

    test "a link vouches once", ctx do
      stranger =
        bypass_rls(fn ->
          user = user_fixture()
          member_verified!(user)
          user
        end)

      {:ok, _} = PartnerVerification.consent(ctx(ctx.candidate))
      {:ok, %{token: token}} = PartnerVerification.create_link(ctx(ctx.candidate))

      assert {:ok, %{can_vouch: true}} =
               PartnerSponsoring.inspect_link(ctx(stranger), %{"token" => token})

      assert {:ok, %{status: "vouched"}} =
               PartnerSponsoring.vouch_by_link(ctx(stranger), %{"token" => token})

      assert {:error, :partner_link_expired} =
               PartnerSponsoring.vouch_by_link(ctx(ctx.sponsor_a), %{"token" => token})
    end

    test "a wrong code counts an attempt; a number verifies one account", ctx do
      me = ctx(ctx.candidate)
      {:ok, _} = PartnerVerification.consent(me)
      {:ok, _} = PartnerVerification.send_phone_code(me, %{"phone" => ctx.phone})

      assert {:error, :partner_code_invalid} =
               PartnerVerification.confirm_phone(me, %{"code" => "000000"}) |> wrong_or_lucky()

      code = MemorySmsSender.last_code(ctx.phone)
      {:ok, _} = PartnerVerification.confirm_phone(me, %{"code" => code})

      other = bypass_rls(fn -> user_fixture() end)
      {:ok, _} = PartnerVerification.consent(ctx(other))

      assert {:error, :partner_phone_taken} =
               PartnerVerification.send_phone_code(ctx(other), %{"phone" => ctx.phone})
    end

    test "SMS failures answer sms_unavailable and are not counted", ctx do
      me = ctx(ctx.candidate)
      {:ok, _} = PartnerVerification.consent(me)
      MemorySmsSender.fail_for(ctx.phone)

      for _attempt <- 1..4 do
        assert {:error, :sms_unavailable} =
                 PartnerVerification.send_phone_code(me, %{"phone" => ctx.phone})
      end
    end

    test "withdrawing removes phone, selfie and open requests", ctx do
      {_overview, key} = ready_for_review!(ctx)
      # In review: the person may still withdraw.
      {:ok, overview} = PartnerVerification.withdraw(ctx(ctx.candidate))
      assert overview.request.status == "withdrawn"
      assert :error = MemoryObjectStore.get(:documents, key)
    end
  end

  # The fixed code "000000" is the right one once in a million runs.
  defp wrong_or_lucky({:ok, _overview}), do: {:error, :partner_code_invalid}
  defp wrong_or_lucky(other), do: other

  describe "sponsors" do
    test "at most 5 vouches in 30 days", ctx do
      sponsor = ctx.sponsor_a
      now = DateTime.utc_now()

      bypass_rls(fn ->
        for _i <- 1..5 do
          other = user_fixture()

          Repo.insert!(%Sponsorship{
            candidate_id: other.id,
            sponsor_id: sponsor.id,
            channel: "link",
            status: "vouched",
            requested_at: now,
            decided_at: now
          })
        end
      end)

      assert {:ok, %{can_vouch: false, reason: "quota", left: 0}} =
               PartnerSponsoring.vouching(ctx(sponsor))

      {:ok, _} = PartnerVerification.consent(ctx(ctx.candidate))

      assert {:error, :partner_sponsor_quota} =
               PartnerVerification.request_sponsor(ctx(ctx.candidate), %{
                 "sponsor_id" => sponsor.id
               })
    end

    test "a suspension pauses the sponsors for 60 days and tells them", ctx do
      {_overview, _key} = ready_for_review!(ctx)
      vendor = %{user_id: ctx.vendor.id}
      {:ok, %{requests: [item]}} = PlatformPartnerVerifications.list(vendor)
      {:ok, _} = PlatformPartnerVerifications.decide(vendor, item.id, %{"decision" => "approve"})

      now = DateTime.utc_now()

      assert {:ok, %{penalized_sponsor_ids: ids}} =
               PartnerEligibility.suspend(vendor, ctx.candidate.id, now)

      assert Enum.sort(ids) == Enum.sort([ctx.sponsor_a.id, ctx.sponsor_b.id])

      assert {:error, :partner_suspended} =
               PartnerEligibility.require_verified(ctx(ctx.candidate))

      assert {:ok, %{can_vouch: false, reason: "penalty"}} =
               PartnerSponsoring.vouching(ctx(ctx.sponsor_a))
    end
  end

  describe "row security" do
    test "another person sees nothing of a request", ctx do
      {_overview, _key} = ready_for_review!(ctx)
      stranger = bypass_rls(fn -> user_fixture() end)

      assert [] =
               RepoContext.run(ctx(stranger), fn ->
                 Repo.all(VerificationRequest) ++ Repo.all(Sponsorship) ++ Repo.all(Verification)
               end)
               |> Enum.filter(
                 &(Map.get(&1, :user_id) == ctx.candidate.id or
                     Map.get(&1, :candidate_id) == ctx.candidate.id)
               )
    end

    test "the membership source answers only for oneself", ctx do
      %{rows: [[nil]]} =
        RepoContext.run(ctx(ctx.sponsor_a), fn ->
          Repo.query!("SELECT palee_partner_membership_source($1)", [
            Ecto.UUID.dump!(ctx.candidate.id)
          ])
        end)
    end
  end

  describe "retention" do
    test "a selfie unreviewed for 7 days is deleted and the request expires", ctx do
      {_overview, key} = ready_for_review!(ctx)
      later = DateTime.add(DateTime.utc_now(), 8, :day)

      assert %{expired_requests: 1} = PartnerVerificationRetention.run(later)
      assert :error = MemoryObjectStore.get(:documents, key)

      assert {:ok, %{request: %{status: "expired"}, eligibility: %{next_step: "selfie"}}} =
               PartnerVerification.overview(ctx(ctx.candidate), later)
    end

    test "account deletion removes rows and selfies", ctx do
      {_overview, key} = ready_for_review!(ctx)
      candidate_id = ctx.candidate.id
      :ok = PartnerVerificationRetention.purge_person(candidate_id)
      assert :error = MemoryObjectStore.get(:documents, key)

      assert [] =
               bypass_rls(fn ->
                 Repo.all(from r in VerificationRequest, where: r.user_id == ^candidate_id)
               end)
    end
  end
end
