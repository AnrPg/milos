defmodule MilosTraining.Finance.Domain.InvoiceNumberTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.InvoiceNumber

  test "formats invoice references with sequence, package segment, and utc timestamp" do
    issued_at = DateTime.from_naive!(~N[2026-06-16 14:03:22], "Etc/UTC")

    assert InvoiceNumber.format(42, issued_at, "online monthly+") ==
             "INV-000042-ONLINEMONTHL-20260616140322"
  end

  test "falls back to MANUAL when the package segment cannot be derived" do
    issued_at = DateTime.from_naive!(~N[2026-06-16 14:03:22], "Etc/UTC")

    assert InvoiceNumber.format(7, issued_at, nil) == "INV-000007-MANUAL-20260616140322"
    assert InvoiceNumber.package_segment("   ---   ") == "MANUAL"
  end
end
