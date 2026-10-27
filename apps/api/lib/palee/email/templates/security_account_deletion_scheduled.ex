defmodule Palee.Email.Templates.SecurityAccountDeletionScheduled do
  @moduledoc "`:security_account_deletion_scheduled` (ADR-208): a profile or the whole login is about to be deleted (with the undo link). Body in `SecurityNotice`."

  use Palee.Email.Templates.SecurityNotice,
    event: :account_deletion_scheduled
end
