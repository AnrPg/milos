defmodule Palee.Facility.Domain.DoorCodeTest do
  use ExUnit.Case, async: true

  alias Palee.Facility.Domain.{DoorCode, MemberCode}

  @key :crypto.strong_rand_bytes(32)
  @location "7d1d5a3e-1d1b-4a4f-9b0e-2f9c1c0f0a11"
  @t0 ~U[2026-10-20 18:00:00Z]

  defp at(seconds), do: DateTime.add(@t0, seconds, :second)

  describe "door code windows" do
    test "a code is accepted in its own window and one either side" do
      code = DoorCode.current(@key, @location, @t0, 30)

      assert :ok = DoorCode.verify(@key, @location, code, at(29), 30)
      assert :ok = DoorCode.verify(@key, @location, code, at(-1), 30)
      assert :ok = DoorCode.verify(@key, @location, code, at(59), 30)
      assert :ok = DoorCode.verify(@key, @location, code, at(-30), 30)
    end

    test "a code dies two windows later and is not valid before its grace" do
      code = DoorCode.current(@key, @location, @t0, 30)

      assert {:error, :invalid_door_code} = DoorCode.verify(@key, @location, code, at(60), 30)
      assert {:error, :invalid_door_code} = DoorCode.verify(@key, @location, code, at(-31), 30)
    end

    test "the code changes every window and seconds until rotation counts down" do
      refute DoorCode.current(@key, @location, @t0, 30) ==
               DoorCode.current(@key, @location, at(30), 30)

      assert DoorCode.current(@key, @location, @t0, 30) ==
               DoorCode.current(@key, @location, at(29), 30)

      assert DoorCode.seconds_until_rotation(@t0, 30) == 30
      assert DoorCode.seconds_until_rotation(at(12), 30) == 18
    end

    test "codes are bound to the key, the location and the rotation" do
      code = DoorCode.current(@key, @location, @t0, 30)
      other = "11111111-2222-4333-8444-555555555555"

      assert {:error, _} =
               DoorCode.verify(:crypto.strong_rand_bytes(32), @location, code, @t0, 30)

      assert {:error, _} = DoorCode.verify(@key, other, code, @t0, 30)
      assert {:error, _} = DoorCode.verify(@key, @location, code, @t0, 60)
      assert {:error, _} = DoorCode.verify(@key, @location, nil, @t0, 30)
      assert {:error, _} = DoorCode.verify(@key, @location, "", @t0, 30)
    end

    test "rotating the door secret (a new key) invalidates every old code" do
      old = DoorCode.current(@key, @location, @t0, 30)
      new_key = :crypto.strong_rand_bytes(32)

      assert {:error, :invalid_door_code} = DoorCode.verify(new_key, @location, old, @t0, 30)

      assert :ok =
               DoorCode.verify(
                 new_key,
                 @location,
                 DoorCode.current(new_key, @location, @t0, 30),
                 @t0,
                 30
               )
    end

    test "codes are short URL-safe strings" do
      code = DoorCode.current(@key, @location, @t0, 30)
      assert byte_size(code) == 16
      assert code =~ ~r/\A[A-Za-z0-9_-]+\z/
    end
  end

  describe "offline batch" do
    test "covers the next windows and no more than about two minutes" do
      for rotation <- [15, 30, 60] do
        batch = DoorCode.batch(@key, @location, at(7), rotation)

        assert length(batch) == DoorCode.batch_size(rotation)
        assert hd(batch).code == DoorCode.current(@key, @location, at(7), rotation)

        last = List.last(batch)

        assert DateTime.diff(last.valid_until, at(7)) <=
                 DoorCode.offline_horizon_seconds() + 2 * rotation

        for entry <- batch do
          assert :ok = DoorCode.verify(@key, @location, entry.code, entry.shows_from, rotation)
          assert DateTime.diff(entry.valid_until, entry.shows_from) == 2 * rotation
        end
      end
    end

    test "a leaked batch is useless after its horizon" do
      batch = DoorCode.batch(@key, @location, @t0, 30)
      later = at(DoorCode.offline_horizon_seconds() + 60)

      for entry <- batch do
        assert {:error, :invalid_door_code} =
                 DoorCode.verify(@key, @location, entry.code, later, 30)
      end
    end

    test "the count cannot reach beyond the horizon" do
      assert length(DoorCode.batch(@key, @location, @t0, 30, 100)) == DoorCode.batch_size(30)
      assert length(DoorCode.batch(@key, @location, @t0, 30, 1)) == 1
    end
  end

  describe "member code" do
    @user "0b6f6c02-8a0c-4a3e-9d6d-7f1e2c3b4a59"

    test "round-trips the user within the grace window" do
      %{code: code, rotation_seconds: 30} = MemberCode.current(@key, @user, @t0)

      assert MemberCode.member_code?(code)
      assert {:ok, @user} = MemberCode.verify(@key, code, at(45))
      assert {:ok, @user} = MemberCode.verify(@key, code, at(-15))
      assert {:error, :invalid_member_code} = MemberCode.verify(@key, code, at(60))
    end

    test "is bound to the box key and cannot be tampered with" do
      %{code: code} = MemberCode.current(@key, @user, @t0)

      assert {:error, :invalid_member_code} =
               MemberCode.verify(:crypto.strong_rand_bytes(32), code, @t0)

      "M1" <> encoded = code
      {:ok, <<_uuid::binary-size(16), mac::binary>>} = Base.url_decode64(encoded, padding: false)
      forged = "M1" <> Base.url_encode64(Ecto.UUID.dump!(@location) <> mac, padding: false)
      assert {:error, :invalid_member_code} = MemberCode.verify(@key, forged, @t0)
      assert {:error, :invalid_member_code} = MemberCode.verify(@key, "M1***", @t0)
      assert {:error, :invalid_member_code} = MemberCode.verify(@key, "door", @t0)
      refute MemberCode.member_code?("W1abc")
    end

    test "expires_at is the end of the grace window" do
      %{expires_at: expires_at, seconds_until_rotation: 20} =
        MemberCode.current(@key, @user, at(10))

      assert expires_at == at(60)
    end
  end
end
