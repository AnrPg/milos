defmodule Palee.Email.Templates.SecurityRecoveryCodesRegenerated do
  @moduledoc "`:security_recovery_codes_regenerated` (ADR-208): new recovery codes replaced the old ones. Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :recovery_codes_regenerated
end
