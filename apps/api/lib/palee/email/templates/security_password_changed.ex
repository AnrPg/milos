defmodule Palee.Email.Templates.SecurityPasswordChanged do
  @moduledoc "`:security_password_changed` (ADR-208): the password was changed in Settings. Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :password_changed
end
