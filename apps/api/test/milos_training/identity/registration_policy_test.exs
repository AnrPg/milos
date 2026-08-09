defmodule MilosTraining.Identity.RegistrationPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Identity.RegistrationPolicy

  describe "normalize_nickname/1" do
    test "downcases and transliterates nicknames without changing the display input" do
      assert RegistrationPolicy.normalize_nickname("Atlas_One") == "atlas_one"
      assert RegistrationPolicy.normalize_nickname("Νίκος_7") == "nikos_7"
      assert RegistrationPolicy.normalize_nickname("Élodie") == "elodie"
    end

    test "passes through nil" do
      assert RegistrationPolicy.normalize_nickname(nil) == nil
    end
  end

  describe "credential validation" do
    test "accepts usernames made of letters, numbers, and underscores" do
      assert RegistrationPolicy.valid_nickname?("Nίκος_7")
      refute RegistrationPolicy.valid_nickname?("ab")
      refute RegistrationPolicy.valid_nickname?("atlas one")
      refute RegistrationPolicy.valid_nickname?("atlas!")
    end

    test "accepts passwords with length, mixed case, a digit, a symbol, and no whitespace" do
      assert RegistrationPolicy.valid_password?("Str0ng!Pass12")
      refute RegistrationPolicy.valid_password?("p@55")
      refute RegistrationPolicy.valid_password?("abc")
      refute RegistrationPolicy.valid_password?("pass word")
      refute RegistrationPolicy.valid_password?("nouppercase1!")
      refute RegistrationPolicy.valid_password?("NOLOWERCASE1!")
      refute RegistrationPolicy.valid_password?("NoDigitsHere!")
      refute RegistrationPolicy.valid_password?("NoSymbols123")
    end
  end

  describe "self_register_roles/0" do
    test "excludes admin from self-registration" do
      assert RegistrationPolicy.self_register_roles() == [:member, :athlete]
      refute :admin in RegistrationPolicy.self_register_roles()
    end
  end
end
