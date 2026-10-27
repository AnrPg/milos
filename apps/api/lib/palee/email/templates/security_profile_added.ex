defmodule Palee.Email.Templates.SecurityProfileAdded do
  @moduledoc "`:security_profile_added` (ADR-208): a profile was added to the login. Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :profile_added
end
