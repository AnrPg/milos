defmodule Palee.Application.ReindexSearchTest do
  # Swaps the global search index adapters.
  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{CreatePR, ReindexSearch}
  alias Palee.Identity.UserContext

  defmodule CapturingIndex do
    def replace_documents(documents) do
      send(self(), {:replaced, documents})
      :ok
    end

    def enqueue_upsert(_pr), do: :ok
    def enqueue_delete(_id, _owner), do: :ok
    def search(_user_id, _query), do: {:ok, []}
  end

  setup do
    previous =
      for key <- [:pr_search_index, :admin_member_search_index],
          do: {key, Application.get_env(:palee, key)}

    Application.put_env(:palee, :pr_search_index, CapturingIndex)
    Application.put_env(:palee, :admin_member_search_index, CapturingIndex)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:palee, key, value) end)
    end)
  end

  test "rebuilds the member index and every member's PRs from the database" do
    member = user_fixture()
    other = user_fixture()
    {:ok, pr} = CreatePR.call(UserContext.new(member), pr_params("Back squat"))
    {:ok, other_pr} = CreatePR.call(UserContext.new(other), pr_params("Deadlift"))

    assert {:ok, %{prs: count}} = ReindexSearch.call()
    assert count >= 2

    assert_received {:replaced, member_documents}
    assert Enum.any?(member_documents, &(&1.id == member.id))

    assert_received {:replaced, pr_documents}
    assert %{id: pr.id, user_id: member.id, name: "Back squat"} in pr_documents
    assert %{id: other_pr.id, user_id: other.id, name: "Deadlift"} in pr_documents
  end

  defp pr_params(name) do
    %{
      "name" => name,
      "current_score" => 120,
      "unit" => "kg",
      "beaten_on" => Date.to_iso8601(Date.utc_today())
    }
  end
end
