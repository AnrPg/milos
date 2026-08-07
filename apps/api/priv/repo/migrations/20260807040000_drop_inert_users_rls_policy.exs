defmodule MilosTraining.Repo.Migrations.DropInertUsersRlsPolicy do
  use Ecto.Migration

  # F-08 / P3.3: `users_owner_policy` was created but Row Level Security was
  # never enabled on `users`, so the policy has never done anything. A disabled
  # policy is worse than no policy — it reads as protection during review.
  #
  # Resolved by removing it rather than enabling it, because the policy is also
  # wrong: `id = app.user_id` would restrict the table to the acting account,
  # and `users` must be readable before any session GUC exists (login by
  # nickname, token verification, tenant resolution) as well as across accounts
  # (admin directory, booking nickname lookups).
  #
  # `users` is therefore application-layer-only by design. `mix
  # milos.tenancy.audit` now reports it under platform-administered tables so
  # the exemption is stated rather than merely absent.

  def up do
    execute("DROP POLICY IF EXISTS users_owner_policy ON users")
  end

  def down do
    execute("""
    CREATE POLICY users_owner_policy ON users
    USING (id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)
  end
end
