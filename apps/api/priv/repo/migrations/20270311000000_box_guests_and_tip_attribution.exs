defmodule Palee.Repo.Migrations.BoxGuestsAndTipAttribution do
  @moduledoc """
  ADR-272: the box role `guest` and who a Tap to Pay tip belongs to.

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
  end

  def down do
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

    replace_role_checks(@old_roles)
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
