defmodule Palee.Fiscal.Domain.TransmissionPolicyTest do
  @moduledoc "ADR-243: transmission states, backoff and deferrals."

  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.TransmissionPolicy, as: Policy

  @now ~U[2027-02-01 10:00:00Z]

  test "backoff grows and stops at a day" do
    gaps = for n <- 1..12, do: DateTime.diff(Policy.next_attempt_at(n, @now), @now)
    assert Enum.take(gaps, 4) == [60, 300, 900, 1_800]
    assert List.last(gaps) == 86_400
    assert gaps == Enum.sort(gaps)
  end

  test "outcomes" do
    t = %{attempts: 3}

    assert %{status: "accepted", mark: "1", accepted_at: @now} =
             Policy.outcome(t, {:ok, %{mark: "1", uid: "u"}}, @now)

    assert %{status: "rejected", last_error_code: "101", last_error_message: "101: a; 102: b"} =
             Policy.outcome(
               t,
               {:error,
                {:rejected, [%{code: "101", message: "a"}, %{code: "102", message: "b"}]}},
               @now
             )

    assert %{status: "pending", attempts: 2, last_error_code: "connection_invalid"} =
             Policy.outcome(t, {:error, {:unauthorized, :x}}, @now)

    assert %{status: "pending", last_error_code: "transient"} =
             Policy.outcome(t, {:error, :timeout}, @now)

    assert %{status: "failed"} =
             Policy.outcome(%{attempts: Policy.max_attempts()}, {:error, :timeout}, @now)
  end

  test "deferrals do not spend attempts; only refused or failed rows are retried" do
    assert %{attempts: 0, status: "pending", last_error_code: "connection_missing"} =
             Policy.deferral(%{attempts: 1}, :connection_missing, @now)

    assert Policy.retryable?(%{status: "rejected"})
    assert Policy.retryable?(%{status: "failed"})
    refute Policy.retryable?(%{status: "accepted"})
    refute Policy.retryable?(%{status: "pending"})
    assert Policy.required?(%{authority: :mydata})
    refute Policy.required?(%{authority: :none})
  end
end
