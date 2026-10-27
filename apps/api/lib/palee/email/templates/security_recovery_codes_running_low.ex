defmodule Palee.Email.Templates.SecurityRecoveryCodesRunningLow do
  @moduledoc "`:security_recovery_codes_running_low` (ADR-208): two or fewer unused recovery codes are left. Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :recovery_codes_running_low
end
