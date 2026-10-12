defmodule MilosTraining.Identity.Domain.AccountExport do
  @moduledoc """
  Export shape for accounts included in a tenant export (ADR-107). Secrets
  (password hashes, token versions) are never exported.
  """

  def to_export(account) do
    %{
      "id" => account.id,
      "nickname" => account.nickname,
      "role" => account.role && to_string(account.role),
      "email" => account.email,
      "preferred_locale" => account.preferred_locale,
      "avatar_url" => account.avatar_url,
      "inserted_at" => account.inserted_at && to_string(account.inserted_at)
    }
  end
end
