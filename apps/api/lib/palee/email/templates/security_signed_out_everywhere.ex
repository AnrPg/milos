defmodule Palee.Email.Templates.SecuritySignedOutEverywhere do
  @moduledoc "`:security_signed_out_everywhere` (ADR-208): every session of the login was ended. Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :signed_out_everywhere
end
