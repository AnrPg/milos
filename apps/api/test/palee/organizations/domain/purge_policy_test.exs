defmodule Palee.Organizations.Domain.PurgePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.PurgePolicy

  describe "transition/2" do
    test "walks the happy path" do
      assert {:ok, :exporting} = PurgePolicy.transition(%{status: :requested}, :start_export)
      assert {:ok, :exported} = PurgePolicy.transition(%{status: :exporting}, :complete_export)
      assert {:ok, :approved} = PurgePolicy.transition(%{status: :exported}, :approve)
      assert {:ok, :purging} = PurgePolicy.transition(%{status: :approved}, :start_purge)
      assert {:ok, :completed} = PurgePolicy.transition(%{status: :purging}, :complete)
    end

    test "approval needs a completed export" do
      for status <- [:requested, :exporting, :failed, :cancelled, :completed] do
        assert {:error, :invalid_purge_transition} =
                 PurgePolicy.transition(%{status: status}, :approve)
      end
    end

    test "failures resume only their own stage" do
      export_failure = %{status: :failed, failed_stage: "export"}
      purge_failure = %{status: :failed, failed_stage: "purge"}

      assert {:ok, :exporting} = PurgePolicy.transition(export_failure, :start_export)
      assert {:error, _} = PurgePolicy.transition(export_failure, :start_purge)
      assert {:ok, :purging} = PurgePolicy.transition(purge_failure, :start_purge)
      assert {:error, _} = PurgePolicy.transition(purge_failure, :start_export)
    end

    test "cancellation is only possible before approval" do
      assert {:ok, :cancelled} = PurgePolicy.transition(%{status: :requested}, :cancel)
      assert {:ok, :cancelled} = PurgePolicy.transition(%{status: :exported}, :cancel)

      assert {:ok, :cancelled} =
               PurgePolicy.transition(%{status: :failed, failed_stage: "export"}, :cancel)

      for status <- [:approved, :purging, :completed] do
        assert {:error, :invalid_purge_transition} =
                 PurgePolicy.transition(%{status: status}, :cancel)
      end

      assert {:error, :invalid_purge_transition} =
               PurgePolicy.transition(%{status: :failed, failed_stage: "purge"}, :cancel)
    end
  end

  test "typed confirmation must match the slug exactly, ignoring surrounding space" do
    assert :ok = PurgePolicy.verify_confirmation("north-gym", "  north-gym ")

    assert {:error, :purge_confirmation_mismatch} =
             PurgePolicy.verify_confirmation("north-gym", "North-Gym")

    assert {:error, :purge_confirmation_mismatch} =
             PurgePolicy.verify_confirmation("north-gym", nil)
  end

  test "approval mode records whether a second vendor reviewed the purge" do
    assert PurgePolicy.approval_mode("a", "a") == "typed_confirmation"
    assert PurgePolicy.approval_mode("a", "b") == "second_vendor"
  end

  describe "lifecycle_change_allowed/2" do
    test "no open purge allows anything" do
      assert :ok = PurgePolicy.lifecycle_change_allowed(nil, :active)
    end

    test "open purges block reactivation, irreversible ones block everything" do
      assert {:error, :organization_purge_in_progress} =
               PurgePolicy.lifecycle_change_allowed(%{status: :exported}, :active)

      assert :ok = PurgePolicy.lifecycle_change_allowed(%{status: :exported}, :archived)

      for status <- [:approved, :purging] do
        assert {:error, :organization_purge_in_progress} =
                 PurgePolicy.lifecycle_change_allowed(%{status: status}, :archived)
      end
    end
  end

  test "resume_stage maps open states to the idempotent background stage" do
    assert {:ok, :export} = PurgePolicy.resume_stage(%{status: :requested})
    assert {:ok, :export} = PurgePolicy.resume_stage(%{status: :failed, failed_stage: "export"})
    assert {:ok, :purge} = PurgePolicy.resume_stage(%{status: :approved})
    assert {:ok, :purge} = PurgePolicy.resume_stage(%{status: :failed, failed_stage: "purge"})
    assert {:error, _} = PurgePolicy.resume_stage(%{status: :exported})
    assert {:error, _} = PurgePolicy.resume_stage(%{status: :completed})
  end

  test "steps are recorded with string keys and detected as completed" do
    at = ~U[2026-10-12 10:00:00Z]
    steps = PurgePolicy.put_step(%{}, :finance, %{deleted: %{finance_invoices: 2}}, at)

    assert steps["finance"]["deleted"]["finance_invoices"] == 2
    assert steps["finance"]["completed_at"] == "2026-10-12T10:00:00Z"
    assert PurgePolicy.step_completed?(steps, "finance")
    refute PurgePolicy.step_completed?(steps, "workouts")
  end

  test "failure reasons are short and PII-free" do
    assert PurgePolicy.failure_reason(:user_has_restricted_history) ==
             "user_has_restricted_history"

    assert PurgePolicy.failure_reason({:object_store_failed, %{email: "x@y"}}) ==
             "object_store_failed"

    assert PurgePolicy.failure_reason("free text with x@y") == "unexpected_failure"
  end
end
