defmodule MilosTraining.Organizations.Domain.SlugRenamePolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.SlugRenamePolicy

  @org "11111111-1111-1111-1111-111111111111"
  @other "22222222-2222-2222-2222-222222222222"

  describe "requested_slug/1" do
    test "accepts a valid slug, trimming and lowercasing it" do
      assert SlugRenamePolicy.requested_slug("  North-Harbor  ") == {:ok, "north-harbor"}
    end

    test "rejects slugs the organization policy rejects instead of re-slugifying them" do
      for invalid <- ["ab", "north harbor", "-north", "north--harbor", "nörth", "", nil, 42] do
        assert SlugRenamePolicy.requested_slug(invalid) == {:error, :invalid_slug}
      end

      assert SlugRenamePolicy.requested_slug(String.duplicate("a", 64)) == {:error, :invalid_slug}
    end
  end

  describe "verify_confirmation/2" do
    test "requires the current slug retyped exactly" do
      assert SlugRenamePolicy.verify_confirmation("north-harbor", " north-harbor ") == :ok

      assert SlugRenamePolicy.verify_confirmation("north-harbor", "North-Harbor") ==
               {:error, :slug_confirmation_mismatch}

      assert SlugRenamePolicy.verify_confirmation("north-harbor", "new-slug") ==
               {:error, :slug_confirmation_mismatch}

      assert SlugRenamePolicy.verify_confirmation("north-harbor", nil) ==
               {:error, :slug_confirmation_mismatch}
    end
  end

  describe "plan/4" do
    test "a free slug retires the current one as an alias" do
      assert SlugRenamePolicy.plan(@org, "old-slug", "new-slug", nil) ==
               {:ok, %{slug: "new-slug", retire: "old-slug", reclaim_alias: false}}
    end

    test "the organization may reclaim one of its own retired aliases" do
      assert SlugRenamePolicy.plan(@org, "new-slug", "old-slug", {:alias, @org}) ==
               {:ok, %{slug: "old-slug", retire: "new-slug", reclaim_alias: true}}
    end

    test "another organization's canonical slug or alias is taken" do
      assert SlugRenamePolicy.plan(@org, "old-slug", "theirs", {:organization, @other}) ==
               {:error, :slug_taken}

      assert SlugRenamePolicy.plan(@org, "old-slug", "their-old", {:alias, @other}) ==
               {:error, :slug_taken}
    end

    test "renaming to the current slug is rejected" do
      assert SlugRenamePolicy.plan(@org, "same", "same", {:organization, @org}) ==
               {:error, :slug_unchanged}
    end
  end
end
