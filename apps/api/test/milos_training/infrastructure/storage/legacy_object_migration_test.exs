defmodule MilosTraining.Infrastructure.Storage.LegacyObjectMigrationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Finance.FinanceInvoice
  alias MilosTraining.Identity.User
  alias MilosTraining.Infrastructure.Storage.LegacyObjectMigration
  alias MilosTraining.Infrastructure.Storage.LegacyObjectMigration.Item
  alias MilosTraining.Repo

  import MilosTraining.TestFixtures

  test "plans legacy invoice file keys under the organization prefix" do
    invoice = %FinanceInvoice{
      id: Ecto.UUID.generate(),
      organization_id: "org-id",
      params: %{"file_key" => "invoices/invoice.pdf"}
    }

    assert %Item{} = item = LegacyObjectMigration.invoice_item(invoice, "docs")
    assert item.source_bucket == "docs"
    assert item.source_key == "invoices/invoice.pdf"
    assert item.destination_key == "organizations/org-id/invoices/invoice.pdf"
  end

  test "ignores already canonical invoice keys" do
    invoice = %FinanceInvoice{
      id: Ecto.UUID.generate(),
      organization_id: "org-id",
      params: %{"file_key" => "organizations/org-id/invoices/invoice.pdf"}
    }

    assert is_nil(LegacyObjectMigration.invoice_item(invoice, "docs"))
  end

  test "plans legacy avatar URLs under the user avatar prefix" do
    user_id = Ecto.UUID.generate()

    user = %User{
      id: user_id,
      avatar_url: "https://media.localhost:18080/milos-avatars/avatars/#{user_id}/profile.jpg"
    }

    assert %Item{} = item = LegacyObjectMigration.avatar_item(user, "milos-avatars")
    assert item.source_key == "avatars/#{user_id}/profile.jpg"
    assert item.destination_key == "users/#{user_id}/avatars/profile.jpg"
  end

  test "rejects avatar URLs that do not belong to the user" do
    user = %User{
      id: Ecto.UUID.generate(),
      avatar_url: "https://media.localhost:18080/milos-avatars/avatars/other/profile.jpg"
    }

    assert is_nil(LegacyObjectMigration.avatar_item(user, "milos-avatars"))
  end

  test "dry-run migration does not touch object storage" do
    item = %Item{
      kind: :invoice,
      record: %FinanceInvoice{id: Ecto.UUID.generate()},
      source_bucket: "docs",
      source_key: "invoices/a.pdf",
      destination_bucket: "docs",
      destination_key: "organizations/org/invoices/a.pdf"
    }

    assert {:planned, ^item} = LegacyObjectMigration.migrate_item(item, apply: false)
  end

  test "apply copies and verifies an avatar before updating the persisted URL" do
    account = user_fixture()
    user = Repo.get!(User, account.id)
    source_key = "avatars/#{user.id}/profile.jpg"
    destination_key = "users/#{user.id}/avatars/profile.jpg"
    body = "image-bytes"

    Process.put({:object, "milos-avatars", source_key}, body)

    {:ok, user} =
      user
      |> Ecto.Changeset.change(
        avatar_url: "https://media.localhost:18080/milos-avatars/#{source_key}"
      )
      |> Repo.update()

    item = LegacyObjectMigration.avatar_item(user, "milos-avatars")

    assert {:migrated, ^item} =
             LegacyObjectMigration.migrate_item(item,
               apply: true,
               object_store: __MODULE__.FakeObjectStore,
               document_config: :ignored,
               avatar_config: :ignored
             )

    assert Process.get({:object, "milos-avatars", destination_key}) == body

    assert Repo.get!(User, user.id).avatar_url ==
             "http://localhost:9000/milos-avatars/#{destination_key}"
  end

  test "apply refuses a pre-existing destination with different bytes" do
    item = %Item{
      kind: :invoice,
      record: %FinanceInvoice{id: Ecto.UUID.generate()},
      source_bucket: "docs",
      source_key: "invoices/a.pdf",
      destination_bucket: "docs",
      destination_key: "organizations/org/invoices/a.pdf"
    }

    Process.put({:object, "docs", "invoices/a.pdf"}, "source")
    Process.put({:object, "docs", "organizations/org/invoices/a.pdf"}, "different")

    assert {:error, ^item, :checksum_mismatch} =
             LegacyObjectMigration.migrate_item(item,
               apply: true,
               object_store: __MODULE__.FakeObjectStore,
               document_config: :ignored,
               avatar_config: :ignored
             )
  end

  defmodule FakeObjectStore do
    def get_object(_config, bucket, key) do
      case Process.get({:object, bucket, key}) do
        nil -> {:error, :object_not_found}
        body -> {:ok, %{body: body}}
      end
    end

    def put_object(_config, bucket, key, body) do
      Process.put({:object, bucket, key}, body)
      :ok
    end

    def delete_object(_config, bucket, key) do
      Process.delete({:object, bucket, key})
      :ok
    end
  end
end
