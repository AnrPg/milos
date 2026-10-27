defmodule Palee.Email.Templates.SecurityPasswordResetCompleted do
  @moduledoc "`:security_password_reset_completed` (ADR-208): the password was reset (reset link). Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :password_reset_completed
end
