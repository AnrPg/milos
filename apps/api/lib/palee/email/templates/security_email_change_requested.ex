defmodule Palee.Email.Templates.SecurityEmailChangeRequested do
  @moduledoc "`:security_email_change_requested` (ADR-208): a change of the login's email was asked for (sent to the current address). Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :email_change_requested
end
