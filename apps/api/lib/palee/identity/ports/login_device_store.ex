defmodule Palee.Identity.Ports.LoginDeviceStore do
  @moduledoc "ADR-208: storage of the devices a login has signed in from."

  alias Palee.Identity.Domain.SignInDevice

  @typedoc """
  What remembering a device found:

    * `:first` - the login had never signed in with a password before (a
      device remembered at sign-up does not count), so nothing is told;
    * `:known` - the device was seen before;
    * `:new` - the login has signed in before, never from this device.
  """
  @type outcome :: :first | :known | :new

  @typedoc "`:sign_in` counts as a sign-in; `:sign_up` only remembers the device."
  @type source :: :sign_in | :sign_up

  @callback remember(
              login_id :: Ecto.UUID.t(),
              device_hash :: binary(),
              SignInDevice.description(),
              source(),
              DateTime.t()
            ) :: outcome()
end
