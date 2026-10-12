defmodule MilosTraining.Workouts.Domain.AssignmentAudiencePolicyTest do
  @moduledoc "ADR-125: who an assignment may target and what a class variant is."
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.AssignmentAudiencePolicy, as: Policy

  describe "classify/2" do
    test "splits athletes and members by their tenant membership role" do
      roles = %{"a1" => :athlete, "m1" => :member, "a2" => :athlete}

      assert {:ok, %{athletes: ["a1", "a2"], members: ["m1"]}} =
               Policy.classify(["a1", "m1", "a2"], roles)
    end

    test "deduplicates assignees while keeping their order" do
      assert {:ok, %{athletes: ["a1"], members: []}} =
               Policy.classify(["a1", "a1"], %{"a1" => :athlete})
    end

    test "rejects staff and users without a membership in the tenant" do
      assert {:error, :invalid_athletes} = Policy.classify(["c1"], %{"c1" => :coach})
      assert {:error, :invalid_athletes} = Policy.classify(["o1"], %{"o1" => :owner})
      assert {:error, :invalid_athletes} = Policy.classify(["x1"], %{})

      assert {:error, :invalid_athletes} =
               Policy.classify(["a1", "x1"], %{"a1" => :athlete, "x1" => nil})
    end

    test "leaves an empty selection to the aggregate's own validation" do
      assert {:ok, %{athletes: [], members: []}} = Policy.classify([], %{})
    end
  end

  describe "validate_class_variant/2" do
    test "a personal assignment (no source slot) may target any valid audience" do
      assert :ok = Policy.validate_class_variant(nil, %{athletes: ["a1"], members: ["m1"]})
    end

    test "a class variant targets exactly one member" do
      assert :ok = Policy.validate_class_variant("slot", %{athletes: [], members: ["m1"]})

      assert {:error, :class_variant_requires_single_member} =
               Policy.validate_class_variant("slot", %{athletes: [], members: ["m1", "m2"]})

      assert {:error, :class_variant_requires_single_member} =
               Policy.validate_class_variant("slot", %{athletes: ["a1"], members: []})

      assert {:error, :class_variant_requires_single_member} =
               Policy.validate_class_variant("slot", %{athletes: ["a1"], members: ["m1"]})

      assert {:error, :class_variant_requires_single_member} =
               Policy.validate_class_variant("slot", %{athletes: [], members: []})
    end
  end

  test "only members need an explicit personal-programming grant" do
    assert Policy.requires_explicit_entitlement?(:member)
    refute Policy.requires_explicit_entitlement?(:athlete)
  end

  test "athletes and members may execute assignments addressed to them; staff may not" do
    assert Policy.may_execute_assignment?(:athlete)
    assert Policy.may_execute_assignment?(:member)
    refute Policy.may_execute_assignment?(:coach)
    refute Policy.may_execute_assignment?(:admin)
    refute Policy.may_execute_assignment?(nil)
  end

  test "derives the assignment kind from the source slot" do
    assert Policy.kind(nil) == "personal"
    assert Policy.kind("slot") == "class_variant"
  end

  test "a variant is shown on the class card only while it is live" do
    assert Policy.live_status?(nil)
    assert Policy.live_status?(:accepted)
    assert Policy.live_status?("accepted")
    refute Policy.live_status?(:rejected)
    refute Policy.live_status?("rejected")
    refute Policy.live_status?(:archived)
  end

  test "a member mode for profile programming defaults to the ADR-071 class swap" do
    assert {:ok, :class_workout} = Policy.member_programming_mode(nil)
    assert {:ok, :class_workout} = Policy.member_programming_mode("class_workout")
    assert {:ok, :class_variant} = Policy.member_programming_mode("class_variant")
    assert {:ok, :personal} = Policy.member_programming_mode("personal")
    assert {:error, :invalid_programming_mode} = Policy.member_programming_mode("everyone")
  end
end
