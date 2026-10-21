defmodule Palee.Facility.Domain.MemberCodePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Facility.Domain.{CheckInRules, DoorCode, MemberCodePolicy, StaticMemberCode}

  @key :crypto.strong_rand_bytes(32)
  @serial "3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
  @rotating CheckInRules.effective(nil)
  @static CheckInRules.effective(%{member_code_mode: "static"})

  describe "static member code" do
    test "the app and the Wallet carry the same code, told apart by channel" do
      app = StaticMemberCode.sign(@key, @serial, :app)
      wallet = StaticMemberCode.sign(@key, @serial, :wallet)

      assert "S1" <> _ = app
      assert "W1" <> _ = wallet
      assert {:ok, @serial, :app} = StaticMemberCode.verify(@key, app)
      assert {:ok, @serial, :wallet} = StaticMemberCode.verify(@key, wallet)
    end

    test "is bound to the box key and its channel; forgeries fail" do
      app = StaticMemberCode.sign(@key, @serial, :app)
      "S1" <> encoded = app

      assert {:error, :invalid_member_code} =
               StaticMemberCode.verify(:crypto.strong_rand_bytes(32), app)

      # Relabelling an app code as a Wallet code breaks its signature.
      assert {:error, :invalid_member_code} = StaticMemberCode.verify(@key, "W1" <> encoded)
      assert {:error, :invalid_member_code} = StaticMemberCode.verify(@key, "S1AAAA")
      assert {:error, :invalid_member_code} = StaticMemberCode.verify(@key, "M1" <> encoded)
      assert {:error, :invalid_member_code} = StaticMemberCode.verify(@key, nil)
    end
  end

  describe "member code mode" do
    test "rules default to rotating and validate the mode" do
      assert @rotating.member_code_mode == "rotating"

      assert {:ok, %{member_code_mode: "static"}} =
               CheckInRules.validate(%{"member_code_mode" => "static"})

      assert {:error, [member_code_mode: _]} = CheckInRules.validate(%{member_code_mode: "fixed"})
    end

    test "Wallet needs static codes" do
      assert {:error, :wallet_requires_static_code} = MemberCodePolicy.wallet_allowed(@rotating)
      assert :ok = MemberCodePolicy.wallet_allowed(@static)
      assert MemberCodePolicy.presented_kind(@rotating) == :rotating
      assert MemberCodePolicy.presented_kind(@static) == :static
    end

    test "the desk takes rotating codes always and static ones only in static mode" do
      for rules <- [@rotating, @static],
          do: assert(:ok = MemberCodePolicy.accept(rules, :rotating))

      assert :ok = MemberCodePolicy.accept(@static, :static_app)
      assert :ok = MemberCodePolicy.accept(@static, :static_wallet)
      assert {:error, :invalid_member_code} = MemberCodePolicy.accept(@rotating, :static_app)
      assert {:error, :invalid_member_code} = MemberCodePolicy.accept(@rotating, :static_wallet)
      assert {:error, :invalid_member_code} = MemberCodePolicy.accept(@static, nil)
    end

    test "kinds and methods follow the prefix" do
      assert MemberCodePolicy.kind("M1x") == :rotating
      assert MemberCodePolicy.kind("S1x") == :static_app
      assert MemberCodePolicy.kind("W1x") == :static_wallet
      assert MemberCodePolicy.kind("door") == nil
      assert MemberCodePolicy.method(:static_wallet) == "wallet"
      assert MemberCodePolicy.method(:static_app) == "member_qr"
      assert MemberCodePolicy.method(:rotating) == "member_qr"
    end

    test "only static → rotating revokes the static codes" do
      assert :revoke_static_codes = MemberCodePolicy.on_change(@static, @rotating)
      assert :none = MemberCodePolicy.on_change(@rotating, @static)
      assert :none = MemberCodePolicy.on_change(@static, @static)
      assert :none = MemberCodePolicy.on_change(@rotating, @rotating)
    end
  end

  describe "poster code" do
    @location "7d1d5a3e-1d1b-4a4f-9b0e-2f9c1c0f0a11"

    test "is static for a seed and dies when the seed is replaced" do
      code = DoorCode.poster_code(@key, @location)

      assert code == DoorCode.poster_code(@key, @location)
      assert :ok = DoorCode.verify_poster(@key, @location, code)

      assert {:error, :invalid_door_code} =
               DoorCode.verify_poster(:crypto.strong_rand_bytes(32), @location, code)

      assert {:error, :invalid_door_code} =
               DoorCode.verify_poster(@key, Ecto.UUID.generate(), code)

      assert {:error, :invalid_door_code} = DoorCode.verify_poster(@key, @location, nil)
      # A poster code is not a rotating door code.
      refute code == DoorCode.current(@key, @location, DateTime.utc_now(), 30)
    end
  end
end
