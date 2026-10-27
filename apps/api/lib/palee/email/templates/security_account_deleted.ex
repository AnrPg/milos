defmodule Palee.Email.Templates.SecurityAccountDeleted do
  @moduledoc "`:security_account_deleted` (ADR-208): a profile or the whole login was deleted. Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :account_deleted
end
