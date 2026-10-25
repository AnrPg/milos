defmodule Palee.Repo.Migrations.PublicAccountsByDefault do
  @moduledoc """
  ADR-193 §2 amended (ANR 2026-10-25): an account is public and searchable
  until its owner makes it private. The column default and the reading of a
  missing settings row (`palee_user_is_public`) flip to public. Rows already
  stored keep their value: a member who has a settings row keeps what it
  says, so nobody who may have chosen private is exposed by this change.
  """

  use Ecto.Migration

  def up do
    alter table(:community_social_settings) do
      modify :private_account, :boolean, null: false, default: false
    end

    public_function("true")
  end

  def down do
    alter table(:community_social_settings) do
      modify :private_account, :boolean, null: false, default: true
    end

    public_function("false")
  end

  defp public_function(missing_row) do
    execute("""
    CREATE OR REPLACE FUNCTION palee_user_is_public(person uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT COALESCE(
        (SELECT NOT s.private_account FROM public.community_social_settings s
         WHERE s.user_id = person),
        #{missing_row})
    $$
    """)
  end
end
