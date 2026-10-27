defmodule Palee.Email.Templates.SecurityNewSignIn do
  @moduledoc "`:security_new_sign_in` (ADR-208): a sign-in from a device the login never used. Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :new_sign_in,
    # Two new devices a minute apart both deserve a notice.
    throttle: %{min_interval_seconds: 0, max_per_day: 10}
end
