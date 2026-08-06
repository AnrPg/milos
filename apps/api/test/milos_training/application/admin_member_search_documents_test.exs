defmodule MilosTraining.Application.AdminMemberSearchDocumentsTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.AdminMemberSearchDocuments
  alias MilosTraining.Organizations
  alias MilosTraining.TestFixtures

  test "each document is tagged with the user's active organization memberships" do
    member = TestFixtures.user_fixture(%{role: :member, nickname: "doc_org_member"})
    {:ok, organization} = Organizations.create_organization(%{name: "Doc Org Search"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    documents = AdminMemberSearchDocuments.build_all()
    document = Enum.find(documents, &(&1.id == member.id))

    assert organization.id in document.organization_ids
  end
end
