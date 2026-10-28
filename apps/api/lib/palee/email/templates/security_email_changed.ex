defmodule Palee.Email.Templates.SecurityEmailChanged do
  @moduledoc "`:security_email_changed` (ADR-208): the login's email changed (sent to the old address, with the undo link). Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :email_changed
end
