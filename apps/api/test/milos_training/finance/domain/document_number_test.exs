defmodule MilosTraining.Finance.Domain.DocumentNumberTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.DocumentNumber

  test "the next sequence follows the counter's last value" do
    assert DocumentNumber.next_sequence(0) == 1
    assert DocumentNumber.next_sequence(41) == 42
  end

  test "refund receipt numbers are prefixed and zero padded to six digits" do
    assert DocumentNumber.format("refund_receipt", 1) == "RFD-000001"
    assert DocumentNumber.format("refund_receipt", 123_456) == "RFD-123456"
    assert DocumentNumber.format("refund_receipt", 1_234_567) == "RFD-1234567"
  end

  test "rejects unknown document types and non-positive sequences" do
    assert_raise FunctionClauseError, fn -> DocumentNumber.format("invoice", 1) end
    assert_raise FunctionClauseError, fn -> DocumentNumber.format("refund_receipt", 0) end
  end

  test "parses formatted numbers back" do
    assert DocumentNumber.parse("RFD-000042") == {:ok, {"refund_receipt", 42}}
    assert DocumentNumber.parse("RFD-0") == :error
    assert DocumentNumber.parse("INV-000001") == :error
    assert DocumentNumber.parse(nil) == :error
  end

  test "detects gaps and duplicates" do
    assert DocumentNumber.gapless?([])
    assert DocumentNumber.gapless?([3, 1, 2])
    refute DocumentNumber.gapless?([1, 3])
    refute DocumentNumber.gapless?([1, 1, 2])
  end
end
