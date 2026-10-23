defmodule Palee.Identity.HandleChangeTest do
  @moduledoc "ADR-187: handle renames are rate-limited and the old handle stays reserved."
  use Palee.DataCase, async: true

  alias Palee.Identity
  import Palee.TestFixtures

  test "a renamed handle is reserved for its former owner, and a second rename waits" do
    user = user_fixture(%{nickname: "old_handle"})
    other = user_fixture()

    assert {:ok, renamed} = Identity.update_profile(user.id, %{handle: "new_handle"})
    assert renamed.handle == "new_handle"

    assert {:error, changeset} = Identity.update_profile(other.id, %{handle: "old_handle"})
    assert "has already been taken" in errors_on(changeset).handle
    refute Identity.handle_available?("old_handle")

    assert {:error, changeset} = Identity.update_profile(user.id, %{handle: "third_handle"})
    assert [message] = errors_on(changeset).handle
    assert message =~ "can be changed again on"

    # The display name is free and changes any time, with no uniqueness.
    assert {:ok, %{nickname: "Same Name"}} =
             Identity.update_profile(user.id, %{display_name: "Same Name"})

    assert {:ok, %{nickname: "Same Name"}} =
             Identity.update_profile(other.id, %{display_name: "Same Name"})
  end
end
