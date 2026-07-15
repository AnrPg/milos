defmodule MilosTraining.Application.AdminSearchUsersTest do
  use MilosTraining.DataCase

  alias MilosTraining.Application.AdminSearchUsers
  alias MilosTraining.Finance
  alias MilosTraining.TestFixtures

  setup do
    previous = Application.get_env(:milos_training, :admin_member_search_index)

    on_exit(fn ->
      Application.put_env(:milos_training, :admin_member_search_index, previous)
    end)

    :ok
  end

  test "empty search does not preload every member" do
    _member = TestFixtures.user_fixture(%{role: :member, nickname: "empty_search_member"})

    assert {:ok, %{users: [], meta: %{empty_search: true}}} = AdminSearchUsers.call(%{})
  end

  test "search results can be sliced by membership status and package metadata" do
    Application.put_env(:milos_training, :admin_member_search_index, __MODULE__.FailingIndex)

    member = TestFixtures.user_fixture(%{role: :member, nickname: "slice_member"})
    athlete = TestFixtures.user_fixture(%{role: :athlete, nickname: "slice_athlete"})

    assert {:ok, package} =
             Finance.create_package(%{
               code: "hybrid_monthly",
               name: "Hybrid Monthly",
               family: "hybrid",
               billing_period: "monthly",
               base_price_cents: 12000
             })

    assert {:ok, membership} =
             Finance.upsert_membership(member.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "admin_created"
             })

    assert {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})

    assert {:ok, _membership} =
             Finance.upsert_membership(athlete.id, %{
               user_type_snapshot: "athlete",
               status: "paused",
               signup_source: "admin_created"
             })

    assert {:ok, %{users: users}} =
             AdminSearchUsers.call(%{
               "role" => "all",
               "membership_status" => "active",
               "package_family" => "hybrid"
             })

    assert Enum.map(users, & &1.id) == [member.id]
  end

  test "package filters are applied before finance summary limiting" do
    Application.put_env(:milos_training, :admin_member_search_index, __MODULE__.FailingIndex)

    target = TestFixtures.user_fixture(%{role: :member, nickname: "package_limit_00_target"})

    assert {:ok, target_package} =
             Finance.create_package(%{
               code: "target_package",
               name: "Target Package",
               family: "target-family",
               billing_period: "monthly",
               base_price_cents: 9000
             })

    assert {:ok, other_package} =
             Finance.create_package(%{
               code: "other_package",
               name: "Other Package",
               family: "other-family",
               billing_period: "monthly",
               base_price_cents: 9000
             })

    assert {:ok, target_membership} =
             Finance.upsert_membership(target.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "admin_created"
             })

    assert {:ok, _subscription} =
             Finance.assign_package(target_membership.id, target_package.id, %{})

    for index <- 1..6 do
      user =
        TestFixtures.user_fixture(%{
          role: :member,
          nickname: "package_limit_0#{index}_other"
        })

      assert {:ok, membership} =
               Finance.upsert_membership(user.id, %{
                 user_type_snapshot: "member",
                 status: "active",
                 signup_source: "admin_created"
               })

      assert {:ok, _subscription} = Finance.assign_package(membership.id, other_package.id, %{})
    end

    assert {:ok, %{users: users}} =
             AdminSearchUsers.call(%{
               "role" => "member",
               "package_code" => "target_package",
               "limit" => "1"
             })

    assert Enum.map(users, & &1.id) == [target.id]
  end

  test "uses indexed member search when the Meilisearch adapter succeeds" do
    Application.put_env(:milos_training, :admin_member_search_index, __MODULE__.CapturingIndex)

    _member = TestFixtures.user_fixture(%{role: :member, nickname: "indexed_member"})

    assert {:ok, %{users: users, meta: meta}} =
             AdminSearchUsers.call(%{"q" => "indexed", "role" => "member", "limit" => "5"})

    assert [%{id: "indexed-user", nickname: "Indexed User"}] = users
    assert meta.search_backend == "fake_index"
    assert meta.empty_search == false
  end

  defmodule FailingIndex do
    @behaviour MilosTraining.Application.Ports.AdminMemberSearchIndex

    @impl true
    def replace_documents(_documents), do: {:error, :offline}

    @impl true
    def search(_params), do: {:error, :offline}
  end

  defmodule CapturingIndex do
    @behaviour MilosTraining.Application.Ports.AdminMemberSearchIndex

    @impl true
    def replace_documents(documents) do
      if Enum.any?(documents, &(&1.nickname == "indexed_member")) do
        :ok
      else
        {:error, :missing_document}
      end
    end

    @impl true
    def search(%{query: "indexed", role: "member", limit: 5}) do
      {:ok,
       %{
         users: [
           %{
             id: "indexed-user",
             nickname: "Indexed User",
             identity_role: "member",
             membership: nil,
             package_subscriptions: [],
             active_package_subscription: nil
           }
         ],
         meta: %{search_backend: "fake_index"}
       }}
    end

    def search(_params), do: {:error, :unexpected_params}
  end
end
