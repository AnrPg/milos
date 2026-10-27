defmodule Palee.Application.SignInDevicesTest do
  use Palee.DataCase, async: true
  use Palee.EmailCase

  alias Palee.Application.SignInDevices
  alias Palee.Identity.LoginDevice
  alias Palee.TestFixtures

  @chrome "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/130.0 Safari/537.36"
  @iphone "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1"

  setup do
    %{person: TestFixtures.user_fixture(%{email: "devices@example.com"})}
  end

  defp context(id, ua \\ @chrome), do: %{device_id: id, user_agent: ua, ip: {198, 51, 100, 9}}

  defp id(name), do: String.pad_trailing("device_" <> name, 24, "x")

  test "the first sign-in of a login never alerts, a known device neither", %{person: person} do
    :ok = SignInDevices.signed_in(person, context(id("laptop")))
    :ok = SignInDevices.signed_in(person, context(id("laptop")))

    refute_email_enqueued(kind: :security_new_sign_in)
    assert [%{sign_ins: 2, client: "Chrome", platform: "Windows"}] = Repo.all(LoginDevice)
  end

  test "a sign-in from a device never seen alerts with the device and a sign-out link", %{
    person: person
  } do
    :ok = SignInDevices.signed_in(person, context(id("laptop")))
    :ok = SignInDevices.signed_in(person, context(id("phone"), @iphone))

    message = assert_email_enqueued(kind: :security_new_sign_in, to: "devices@example.com")
    assert message.subject == "New sign-in to your account"
    assert message.text =~ "Device: Safari on iPhone"
    assert message.text =~ "IP address: 198.51.100.x"
    assert message.text =~ "/sign-out-everywhere#token="
  end

  test "the device used to sign up is known; the first sign-in after sign-up never alerts", %{
    person: person
  } do
    :ok = SignInDevices.signed_up(person, context(id("signup")))
    # First password sign-in, from another device: still no alert.
    :ok = SignInDevices.signed_in(person, context(id("phone"), @iphone))
    # Back on the sign-up device: known.
    :ok = SignInDevices.signed_in(person, context(id("signup")))
    refute_email_enqueued(kind: :security_new_sign_in)

    :ok = SignInDevices.signed_in(person, context(id("tablet")))
    assert_email_enqueued(kind: :security_new_sign_in)
  end

  test "the same id in another kind of browser is a new device", %{person: person} do
    :ok = SignInDevices.signed_in(person, context(id("laptop")))
    :ok = SignInDevices.signed_in(person, context(id("laptop"), @iphone))
    assert_email_enqueued(kind: :security_new_sign_in)
  end

  test "only a hash of the device id is stored", %{person: person} do
    :ok = SignInDevices.signed_in(person, context(id("laptop")))
    [device] = Repo.all(LoginDevice)
    assert byte_size(device.device_hash) == 32
    refute device.device_hash =~ id("laptop")
  end

  test "an account without a login or a device id is ignored" do
    assert :ok = SignInDevices.signed_in(%{id: Ecto.UUID.generate()}, context(id("x")))
    assert :ok = SignInDevices.signed_in(%{login_id: Ecto.UUID.generate()}, %{})
    assert Repo.all(LoginDevice) == []
  end
end
