defmodule Palee.Repo.Migrations.BoxGuestsAndTipAttribution do
  @moduledoc """
  ADR-272: the box role `guest` and who a Tap to Pay tip belongs to.

    * `memberships.user_type_snapshot` admits `guest` (a guest's finance
      profile, so they can buy at the desk).
    * `palee_add_box_guest(org, user)`: front desk and coaches make someone
      a guest of their box (memberships are otherwise written by owners and
      admins only).

    * `organization_memberships.role` / `roles` and
      `registration_invitations.role` / `roles` admit `guest`: a person
      with an account who is a guest of a box (the lowest client-type
      role; it may be the only role of a membership).
    * `payment_intents.tip_recipient_user_id` / `tip_recipient_role` /
      `tip_attribution`: whose tip it is, written once when a payment with
      a tip succeeds. Either a person (`started_payment`: the staff member
      who started it on their phone; `sole_front_desk`: the box's only
      front desk person) or the front desk role unpersonalised
      (`front_desk_role`).
  """

  use Ecto.Migration

  @old_roles ~w(owner admin coach front_desk accountant janitor member athlete)
  @roles @old_roles ++ ["guest"]

  def up do
    replace_role_checks(@roles)
    replace_user_type_check(~w(member athlete guest))

    alter table(:payment_intents) do
      add :tip_recipient_user_id, :binary_id
      add :tip_recipient_role, :string
      add :tip_attribution, :string
    end

    create constraint(:payment_intents, :payment_intents_tip_attribution_check,
             check: """
             (tip_attribution IS NULL AND tip_recipient_user_id IS NULL AND tip_recipient_role IS NULL)
             OR (tip_attribution IN ('started_payment', 'sole_front_desk')
                 AND tip_recipient_user_id IS NOT NULL AND tip_recipient_role IS NULL)
             OR (tip_attribution = 'front_desk_role'
                 AND tip_recipient_user_id IS NULL AND tip_recipient_role = 'front_desk')
             """
           )

    create index(:payment_intents, [:organization_id, :succeeded_at],
             where: "tip_cents > 0",
             name: :payment_intents_tips_index
           )

    # Memberships are written by owners and admins only (RLS). Front desk
    # and coaches may make someone a guest of their box, and nothing else:
    # this function checks the acting person and writes only a guest
    # membership for someone with no active one.
    execute("""
    CREATE OR REPLACE FUNCTION palee_add_box_guest(org_id uuid, guest_user_id uuid)
    RETURNS uuid
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      actor uuid := NULLIF(current_setting('app.user_id', true), '')::uuid;
      existing public.organization_memberships%ROWTYPE;
      new_id uuid;
    BEGIN
      IF actor IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = actor
          AND om.status = 'active'
          AND om.roles && ARRAY['owner', 'admin', 'coach', 'front_desk']::varchar[]
      ) THEN
        RAISE EXCEPTION 'palee_add_box_guest: not allowed' USING ERRCODE = '42501';
      END IF;

      SELECT * INTO existing FROM public.organization_memberships
       WHERE organization_id = org_id AND user_id = guest_user_id
       FOR UPDATE;

      IF FOUND AND existing.status = 'active' THEN
        RETURN existing.id;
      ELSIF FOUND THEN
        UPDATE public.organization_memberships
           SET role = 'guest', roles = ARRAY['guest']::varchar[], status = 'active',
               coach_scope = 'own', invited_by_user_id = actor, updated_at = now()
         WHERE id = existing.id;
        RETURN existing.id;
      END IF;

      INSERT INTO public.organization_memberships
        (id, organization_id, user_id, role, roles, status, joined_at, invited_by_user_id,
         inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), org_id, guest_user_id, 'guest', ARRAY['guest']::varchar[], 'active',
         now(), actor, now(), now())
      RETURNING id INTO new_id;

      RETURN new_id;
    END;
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_add_box_guest(uuid, uuid)")

    drop index(:payment_intents, [:organization_id, :succeeded_at],
           name: :payment_intents_tips_index
         )

    drop constraint(:payment_intents, :payment_intents_tip_attribution_check)

    alter table(:payment_intents) do
      remove :tip_attribution
      remove :tip_recipient_role
      remove :tip_recipient_user_id
    end

    execute("""
    UPDATE organization_memberships
       SET roles = CASE WHEN array_remove(roles, 'guest') = '{}' THEN ARRAY['member']::varchar[]
                        ELSE array_remove(roles, 'guest') END
     WHERE 'guest' = ANY(roles)
    """)

    execute("UPDATE organization_memberships SET role = roles[1] WHERE role = 'guest'")

    execute("""
    UPDATE registration_invitations
       SET roles = CASE WHEN array_remove(roles, 'guest') = '{}' THEN ARRAY['member']::varchar[]
                        ELSE array_remove(roles, 'guest') END
     WHERE 'guest' = ANY(roles)
    """)

    execute("UPDATE registration_invitations SET role = roles[1] WHERE role = 'guest'")

    execute("UPDATE memberships SET user_type_snapshot = 'member' WHERE user_type_snapshot = 'guest'")
    replace_user_type_check(~w(member athlete))
    replace_role_checks(@old_roles)
  end

  # The finance profile of a guest of the box (who may buy at the desk).
  defp replace_user_type_check(types) do
    drop constraint(:memberships, :memberships_user_type_snapshot_check)

    create constraint(:memberships, :memberships_user_type_snapshot_check,
             check: "user_type_snapshot IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end

  defp replace_role_checks(roles) do
    list = Enum.map_join(roles, ", ", &"'#{&1}'")

    drop constraint(:organization_memberships, :organization_memberships_role_check)
    drop constraint(:organization_memberships, :organization_memberships_roles_check)

    create constraint(:organization_memberships, :organization_memberships_role_check,
             check: "role IN (#{list})"
           )

    create constraint(:organization_memberships, :organization_memberships_roles_check,
             check: "cardinality(roles) > 0 AND roles <@ ARRAY[#{list}]::varchar[]"
           )

    drop constraint(:registration_invitations, :registration_invitations_role_check)
    drop constraint(:registration_invitations, :registration_invitations_roles_check)

    create constraint(:registration_invitations, :registration_invitations_role_check,
             check: "role IN (#{list})"
           )

    create constraint(:registration_invitations, :registration_invitations_roles_check,
             check: "roles <@ ARRAY[#{list}]::varchar[]"
           )
  end
end
