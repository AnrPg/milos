defmodule Palee.BoxScreens.Domain.PairingCodeTest do
  use ExUnit.Case, async: true

  alias Palee.BoxScreens.Domain.PairingCode

  test "codes are 8 symbols without look-alikes, shown as ABCD-EFGH" do
    for _ <- 1..200 do
      code = PairingCode.generate()
      assert code =~ ~r/^[A-Z0-9]{4}-[A-Z0-9]{4}$/

      code
      |> String.replace("-", "")
      |> String.graphemes()
      |> Enum.each(fn symbol ->
        assert String.contains?(PairingCode.alphabet(), symbol)
        refute symbol in ~w(0 O D Q 1 I L 2 Z 5 S 8 B U V)
      end)
    end

    assert 200 ==
             1..200 |> Enum.map(fn _ -> PairingCode.generate() end) |> Enum.uniq() |> length()
  end

  test "typing ignores case, spaces and dashes; anything else is refused" do
    assert {:ok, "ACEF3467"} = PairingCode.normalize(" acef-3467 ")
    assert {:ok, "ACEF3467"} = PairingCode.normalize("AC EF 34 67")
    assert :error = PairingCode.normalize("ACEF-346")
    assert :error = PairingCode.normalize("ACEF-3460")
    assert :error = PairingCode.normalize(nil)
  end

  test "only the SHA-256 of the canonical code is kept" do
    assert {:ok, hash} = PairingCode.hash("acef-3467")
    assert hash == :crypto.hash(:sha256, "ACEF3467")
    assert byte_size(hash) == 32
    assert {:ok, ^hash} = PairingCode.hash("ACEF3467")
    assert :error = PairingCode.hash("nope")
  end

  test "a code works for 15 minutes" do
    now = ~U[2027-02-09 10:00:00Z]
    assert PairingCode.expires_at(now) == ~U[2027-02-09 10:15:00Z]
  end
end
