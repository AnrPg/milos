defmodule Palee.Email.Templates.SecurityRecoveryCodeUsed do
  @moduledoc "`:security_recovery_code_used` (ADR-208): a recovery code set a new password. Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :recovery_code_used
end
