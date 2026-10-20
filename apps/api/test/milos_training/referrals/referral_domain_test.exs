defmodule MilosTraining.Referrals.ReferralDomainTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Referrals.Domain.{Attribution, Code}

  @now ~U[2026-10-20 10:00:00Z]

  describe "codes" do
    test "are eight Crockford characters" do
      for _ <- 1..200 do
        code = Code.generate()
        assert Code.valid?(code)
        assert {:ok, ^code} = Code.normalize(code)
      end
    end

    test "read forgivingly: case, spaces, dashes and look-alike letters" do
      assert {:ok, "0K1M2N1A"} = Code.normalize(" ok1m-2n la ")
      assert {:ok, "0K1M2N1A"} = Code.normalize("oK_iM2N1a")
    end

    test "refuse anything else" do
      assert :error = Code.normalize("SHORT")
      assert :error = Code.normalize("ABCDEFGHU")
      assert :error = Code.normalize("ABCDEFG!")
      assert :error = Code.normalize(nil)
      refute Code.valid?("ABCDEFGU")
    end
  end

  describe "claiming" do
    defp facts(overrides) do
      Map.merge(
        %{referrer_id: "a", referred_id: "f", referred_standing: :none, existing: nil, now: @now},
        overrides
      )
    end

    defp open(overrides \\ %{}) do
      Map.merge(
        %{
          referrer_user_id: "a",
          status: "open",
          expires_at: DateTime.add(@now, 10, :day),
          event_at: nil,
          trial_at: nil,
          joined_at: nil,
          paid_at: nil
        },
        overrides
      )
    end

    test "a new friend is recorded" do
      assert :ok = Attribution.claim(facts(%{}))
    end

    test "nobody invites themselves" do
      assert {:error, :self_referral} = Attribution.claim(facts(%{referred_id: "a"}))
    end

    test "members and former members are not friends to win" do
      assert {:error, :already_member} = Attribution.claim(facts(%{referred_standing: :member}))
      assert {:error, :already_member} = Attribution.claim(facts(%{referred_standing: :former}))
    end

    test "the link the friend used owns the invite until it counts" do
      existing = open()
      assert {:existing, ^existing} = Attribution.claim(facts(%{existing: existing}))

      assert {:switch, ^existing} =
               Attribution.claim(facts(%{referrer_id: "b", existing: existing}))

      for counted <- [open(%{status: "qualified"}), open(%{status: "capped"})] do
        assert {:error, :already_invited} =
                 Attribution.claim(facts(%{referrer_id: "b", existing: counted}))
      end

      # Staff gave it to someone: it stands.
      assigned = open(%{reassigned_at: @now})

      assert {:error, :already_invited} =
               Attribution.claim(facts(%{referrer_id: "b", existing: assigned}))
    end

    test "an invite that ran out leaves room for a new one" do
      past = open(%{expires_at: DateTime.add(@now, -1, :day)})
      assert :ok = Attribution.claim(facts(%{referrer_id: "b", existing: past}))

      for status <- ~w(expired void) do
        assert :ok =
                 Attribution.claim(facts(%{referrer_id: "b", existing: open(%{status: status})}))
      end

      assert {:error, :already_invited} =
               Attribution.claim(
                 facts(%{referrer_id: "b", existing: open(%{status: "qualified"})})
               )
    end

    test "the window defaults to 30 days" do
      assert Attribution.expires_at(@now, 45) == DateTime.add(@now, 45, :day)
      assert Attribution.expires_at(@now, nil) == DateTime.add(@now, 30, :day)
    end
  end

  describe "the funnel" do
    test "stamps each step once" do
      assert {:ok, %{trial_at: @now}} = Attribution.advance(open(), :trial, @now)
      assert :noop = Attribution.advance(open(%{trial_at: @now}), :trial, @now)
    end

    test "a step after the window expires the invite" do
      late = DateTime.add(@now, 11, :day)
      assert {:expire, %{status: "expired"}} = Attribution.advance(open(), :paid, late)
    end

    test "qualified invites keep showing progress; ended ones don't move" do
      late = DateTime.add(@now, 90, :day)

      assert {:ok, %{paid_at: ^late}} =
               Attribution.advance(open(%{status: "qualified"}), :paid, late)

      for status <- ~w(expired void capped) do
        assert :noop = Attribution.advance(open(%{status: status}), :paid, @now)
      end
    end

    test "the stage is the furthest step" do
      assert Attribution.stage(open()) == "signed_up"
      assert Attribution.stage(open(%{event_at: @now})) == "event"
      assert Attribution.stage(open(%{event_at: @now, trial_at: @now})) == "trial"
      assert Attribution.stage(open(%{joined_at: @now})) == "joined"
      assert Attribution.stage(open(%{trial_at: @now, paid_at: @now})) == "paid"
    end

    test "qualifies on the programme's step" do
      trial = %{qualifying_stage: "trial"}
      paid = %{qualifying_stage: "paid"}

      refute Attribution.qualifies?(open(), trial)
      assert Attribution.qualifies?(open(%{trial_at: @now}), trial)
      assert Attribution.qualifies?(open(%{paid_at: @now}), trial)
      refute Attribution.qualifies?(open(%{trial_at: @now}), paid)
      assert Attribution.qualifies?(open(%{paid_at: @now}), paid)
      refute Attribution.qualifies?(open(%{status: "qualified", paid_at: @now}), paid)
    end

    test "the yearly cap" do
      refute Attribution.cap_reached?(50, nil)
      refute Attribution.cap_reached?(2, 3)
      assert Attribution.cap_reached?(3, 3)
    end
  end

  describe "reassigning" do
    test "moves the invite and remembers who had it" do
      assert {:ok, changes} =
               Attribution.reassign(
                 open(%{referred_user_id: "f"}),
                 "b",
                 "staff",
                 "Ήρθε με τον Β",
                 @now
               )

      assert changes.referrer_user_id == "b"
      assert changes.previous_referrer_user_id == "a"
      assert changes.code_id == nil
      assert changes.reassigned_by_id == "staff"
    end

    test "never to the friend, never after it counted" do
      assert {:error, :self_referral} =
               Attribution.reassign(open(%{referred_user_id: "f"}), "f", "staff", nil, @now)

      assert {:error, :referral_already_qualified} =
               Attribution.reassign(
                 open(%{referred_user_id: "f", status: "qualified"}),
                 "b",
                 "staff",
                 nil,
                 @now
               )
    end
  end
end
