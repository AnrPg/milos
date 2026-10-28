defmodule Palee.Identity.Domain.SignInDeviceTest do
  use ExUnit.Case, async: true

  alias Palee.Identity.Domain.SignInDevice

  test "a device id is 16-128 url-safe characters" do
    assert SignInDevice.valid_id?(SignInDevice.generate_id())
    assert SignInDevice.valid_id?(String.duplicate("a", 16))
    refute SignInDevice.valid_id?(String.duplicate("a", 15))
    refute SignInDevice.valid_id?(String.duplicate("a", 129))
    refute SignInDevice.valid_id?("has spaces in it!!")
    refute SignInDevice.valid_id?(nil)
  end

  test "the user agent is reduced to a client and a platform" do
    assert SignInDevice.describe(
             "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
           ) == %{client: "Safari", platform: "iPhone"}

    assert SignInDevice.describe(
             "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36 PaleeApp"
           ) == %{client: "app", platform: "Android"}

    assert SignInDevice.describe(
             "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0; rv:131.0) Gecko/20100101 Firefox/131.0"
           ) == %{client: "Firefox", platform: "macOS"}

    assert SignInDevice.describe(
             "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/130.0 Safari/537.36 Edg/130.0"
           ) == %{client: "Edge", platform: "Windows"}

    assert SignInDevice.describe("curl/8.0") == %{client: nil, platform: nil}
    assert SignInDevice.describe(nil) == %{client: nil, platform: nil}
  end

  test "the hash binds the id to the kind of browser" do
    chrome = %{client: "Chrome", platform: "Windows"}
    id = SignInDevice.generate_id()

    assert SignInDevice.hash(id, chrome) == SignInDevice.hash(id, chrome)
    refute SignInDevice.hash(id, chrome) == SignInDevice.hash(id, %{chrome | client: "Firefox"})
    refute SignInDevice.hash(id, chrome) =~ id
  end

  test "an address is shortened to its network part" do
    assert SignInDevice.coarse_ip({203, 0, 113, 77}) == "203.0.113.x"
    assert SignInDevice.coarse_ip({0x2001, 0xDB8, 0x85A3, 0, 0, 0, 0, 1}) == "2001:DB8:85A3::x"
    assert SignInDevice.coarse_ip(nil) == nil
  end
end
