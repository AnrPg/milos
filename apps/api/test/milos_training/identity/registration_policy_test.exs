defmodule MilosTraining.Identity.RegistrationPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Identity.RegistrationPolicy

  describe "normalize_nickname/1" do
    test "trims and downcases nicknames" do
      assert RegistrationPolicy.normalize_nickname("  Atlas_One  ") == "atlas_one"
    end

    test "passes through nil" do
      assert RegistrationPolicy.normalize_nickname(nil) == nil
    end
  end

  describe "self_register_roles/0" do
    test "excludes admin from self-registration" do
      assert RegistrationPolicy.self_register_roles() == [:member, :athlete]
      refute :admin in RegistrationPolicy.self_register_roles()
    end
  end
end
