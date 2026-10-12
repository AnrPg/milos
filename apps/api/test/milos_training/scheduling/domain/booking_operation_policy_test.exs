defmodule MilosTraining.Scheduling.Domain.BookingOperationPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Scheduling.Domain.BookingOperationPolicy

  @op "5f0c9f8e-1d2b-4c3a-9e8f-7a6b5c4d3e2f"
  @other_op "0e1d2c3b-4a59-4687-9a1b-2c3d4e5f6a7b"

  describe "submission_replay/2" do
    test "replays a booking created for the same class" do
      assert :replay =
               BookingOperationPolicy.submission_replay(%{scheduled_class_id: "slot"}, "slot")
    end

    test "reports a conflict when the key was used for another class" do
      assert {:error, :idempotency_key_conflict} =
               BookingOperationPolicy.submission_replay(%{scheduled_class_id: "slot"}, "other")
    end
  end

  describe "resolution_decision/3" do
    test "proceeds while the booking is pending, with or without an operation id" do
      booking = %{status: :pending, resolution_operation_id: nil}

      assert :proceed = BookingOperationPolicy.resolution_decision(booking, :approved, @op)
      assert :proceed = BookingOperationPolicy.resolution_decision(booking, :rejected, nil)
    end

    test "replays the exact resolution that already ran" do
      booking = %{status: :approved, resolution_operation_id: @op}
      assert :replay = BookingOperationPolicy.resolution_decision(booking, :approved, @op)
    end

    test "rejects reusing an operation id for a different outcome" do
      booking = %{status: :approved, resolution_operation_id: @op}

      assert {:error, :idempotency_key_conflict} =
               BookingOperationPolicy.resolution_decision(booking, :rejected, @op)
    end

    test "keeps bookings resolved elsewhere as a not-pending conflict" do
      booking = %{status: :rejected, resolution_operation_id: @other_op}

      assert {:error, :booking_not_pending} =
               BookingOperationPolicy.resolution_decision(booking, :rejected, @op)

      assert {:error, :booking_not_pending} =
               BookingOperationPolicy.resolution_decision(
                 %{status: :cancelled, resolution_operation_id: nil},
                 :approved,
                 nil
               )
    end
  end

  describe "normalize_operation_id/1" do
    test "accepts missing and UUID values" do
      assert {:ok, nil} = BookingOperationPolicy.normalize_operation_id(nil)
      assert {:ok, nil} = BookingOperationPolicy.normalize_operation_id("")
      assert {:ok, @op} = BookingOperationPolicy.normalize_operation_id(String.upcase(@op))
    end

    test "rejects anything else" do
      assert {:error, [client_operation_id: _]} =
               BookingOperationPolicy.normalize_operation_id("not-a-uuid")

      assert {:error, [client_operation_id: _]} =
               BookingOperationPolicy.normalize_operation_id(42)
    end
  end
end
