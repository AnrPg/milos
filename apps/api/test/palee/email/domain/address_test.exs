defmodule Palee.Email.Domain.AddressTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Domain.{Address, DeliveryPolicy}

  test "addresses are normalised and validated" do
    assert {:ok, "jo@box.test"} = Address.normalize("  Jo@Box.Test ")
    assert {:error, :invalid_address} = Address.normalize("jo@box")
    assert {:error, :invalid_address} = Address.normalize("Jo <jo@box.test>")
    assert {:error, :invalid_address} = Address.normalize("jo@box.test\r\nBcc: x@y.z")
    assert {:error, :invalid_address} = Address.normalize(nil)
    assert Address.digest("JO@box.test") == :crypto.hash(:sha256, "jo@box.test")
  end

  test "delivery retries back off exponentially and stop on permanent errors" do
    assert DeliveryPolicy.max_attempts() == 8
    assert Enum.map(1..8, &DeliveryPolicy.backoff/1) == [60, 120, 240, 480, 960, 1920, 3600, 3600]
    assert DeliveryPolicy.permanent?({:send, {:permanent_failure, "relay", "550 no such user"}})
    refute DeliveryPolicy.permanent?(:mail_delivery_unavailable)
  end
end
