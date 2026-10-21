defmodule Palee.Workers.RebuildMemberSearchIndexJobTest do
  use Palee.DataCase, async: false

  alias Palee.{Finance, Organizations}
  alias Palee.TestFixtures
  alias Palee.Workers.RebuildMemberSearchIndexJob

  defmodule CapturingIndex do
    @behaviour Palee.Application.Ports.AdminMemberSearchIndex

    @impl true
    def replace_documents(documents) do
      send(Process.get(:rebuild_test_pid) || self(), {:replaced, documents})
      :ok
    end

    @impl true
    def search(_params), do: {:error, :offline}
  end

  setup do
    previous = Application.get_env(:palee, :admin_member_search_index)
    Application.put_env(:palee, :admin_member_search_index, CapturingIndex)
    on_exit(fn -> Application.put_env(:palee, :admin_member_search_index, previous) end)
    :ok
  end

  test "rebuilds member documents with package types as the reporting family" do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member, nickname: "rebuild_member"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Rebuild #{System.unique_integer([:positive])}"})

    for {user, role} <- [{owner, :owner}, {member, :member}] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", owner.id])

    {:ok, pack} = Finance.create_package(%{name: "Ten visits", package_type: "class_pack"})

    {:ok, membership} =
      Finance.upsert_membership(member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _} = Finance.assign_package(membership.id, pack.id, %{})

    assert :ok = RebuildMemberSearchIndexJob.perform(%Oban.Job{args: %{}})
    assert_received {:replaced, documents}

    document = Enum.find(documents, &(&1["id"] == member.id or &1[:id] == member.id))
    assert document
    families = document["package_families"] || document[:package_families]
    assert "class_pack" in families
  end
end
