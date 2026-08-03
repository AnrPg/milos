defmodule MilosTraining.Organizations.T4OwnershipFoundationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.{Organizations, Repo}

  import MilosTraining.TestFixtures

  test "the stable legacy organization owns transitional tenant data" do
    user = user_fixture()

    assert %{id: legacy_organization_id} =
             Organizations.get_by_slug("legacy-milos-training")

    {:ok, _membership} = Organizations.ensure_legacy_membership(user, :owner)

    assert [%{membership: %{role: :owner}, organization: %{id: ^legacy_organization_id}}] =
             Organizations.list_memberships(user.id)

    %{rows: [[organization_id]]} =
      Repo.query!("""
      INSERT INTO class_types (id, name, slug, sort_order, inserted_at, updated_at)
      VALUES (gen_random_uuid(), 'Legacy Test', 'legacy-test', 0, now(), now())
      RETURNING organization_id
      """)

    assert {:ok, ^legacy_organization_id} = Ecto.UUID.load(organization_id)
  end

  test "tenant policies are installed without being enabled before T6" do
    %{rows: rows} =
      Repo.query!("""
      SELECT policyname
      FROM pg_policies
      WHERE tablename = 'scheduled_classes'
      """)

    assert ["scheduled_classes_tenant_policy"] in rows

    %{rows: [[rls_enabled]]} =
      Repo.query!("""
      SELECT relrowsecurity
      FROM pg_class
      WHERE oid = 'scheduled_classes'::regclass
      """)

    refute rls_enabled
  end
end
