defmodule MilosTraining.Organizations.Domain.OrganizationPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.OrganizationPolicy

  test "normalizes client names into stable URL-safe slugs" do
    assert OrganizationPolicy.normalize_slug("  Acme Gym & Fitness  ") ==
             "acme-gym-fitness"

    assert OrganizationPolicy.normalize_slug("Mýlos   Strength") == "mylos-strength"
  end

  test "accepts bounded slugs without ambiguous separators" do
    assert OrganizationPolicy.valid_slug?("acme-gym")
    refute OrganizationPolicy.valid_slug?("-acme")
    refute OrganizationPolicy.valid_slug?("acme--gym")
    refute OrganizationPolicy.valid_slug?(String.duplicate("a", 64))
  end

  test "publishes the database-backed lifecycle states" do
    assert OrganizationPolicy.statuses() == [:active, :suspended, :archived]
  end
end
