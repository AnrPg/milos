defmodule MilosTraining.Organizations.T4OwnershipFoundationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.{Organizations, Repo}

  import MilosTraining.TestFixtures

  test "the stable legacy organization owns transitional tenant data" do
    user = user_fixture()

    assert %{id: legacy_organization_id} =
             Organizations.get_by_slug("legacy-milos-training")

    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(user, :owner)

    assert [%{membership: %{role: :owner}, organization: %{id: ^legacy_organization_id}}] =
             Organizations.list_memberships(user.id)

    # Writes are fail-closed by design (F-XX/e3c8ae5): the legacy org is no
    # longer an implicit default for unscoped inserts, it's just an ordinary
    # organization that a write can be explicitly scoped to, same as any
    # other tenant. class_types has no BEFORE INSERT tenant-context trigger,
    # so a raw SQL insert (unlike an Ecto changeset going through the app's
    # write paths) must supply organization_id itself.
    %{rows: [[organization_id]]} =
      Repo.query!(
        """
        INSERT INTO class_types (id, name, slug, sort_order, organization_id, inserted_at, updated_at)
        VALUES (gen_random_uuid(), 'Legacy Test', 'legacy-test', 0, $1, now(), now())
        RETURNING organization_id
        """,
        [Ecto.UUID.dump!(legacy_organization_id)]
      )

    assert {:ok, ^legacy_organization_id} = Ecto.UUID.load(organization_id)
  end

  test "scheduling tenant policies are enabled and forced for T6" do
    %{rows: rows} =
      Repo.query!("""
      SELECT policyname
      FROM pg_policies
      WHERE tablename = 'scheduled_classes'
      """)

    assert ["scheduled_classes_tenant_policy"] in rows

    %{rows: [[rls_enabled, rls_forced]]} =
      Repo.query!("""
      SELECT relrowsecurity, relforcerowsecurity
      FROM pg_class
      WHERE oid = 'scheduled_classes'::regclass
      """)

    assert rls_enabled
    assert rls_forced
  end
end
