defmodule Palee.Imports.Domain.DateParserTest do
  use ExUnit.Case, async: true

  alias Palee.Imports.Domain.DateParser

  test "the import's order decides ambiguous dates" do
    assert {:ok, ~D[2025-04-03]} = DateParser.parse("03/04/2025", "dmy")
    assert {:ok, ~D[2025-03-04]} = DateParser.parse("03/04/2025", "mdy")
    assert {:ok, ~D[2025-04-03]} = DateParser.parse("25.04.03", "ymd")
    assert {:ok, ~D[2025-04-03]} = DateParser.parse("3-4-25", "dmy")
  end

  test "ISO dates and times after the date" do
    assert {:ok, ~D[2025-03-04]} = DateParser.parse("2025-03-04", "mdy")
    assert {:ok, ~D[2025-03-04]} = DateParser.parse("2025-03-04 18:30", "dmy")
    assert {:ok, ~D[2025-03-04]} = DateParser.parse("2025-03-04T18:30:00Z", "dmy")
    assert {:ok, ~D[2025-03-04]} = DateParser.parse("3/4/2025 6:30 PM", "mdy")
  end

  test "month names in English and Greek" do
    assert {:ok, ~D[2025-03-04]} = DateParser.parse("4 Mar 2025", "mdy")
    assert {:ok, ~D[2025-03-04]} = DateParser.parse("March 4, 2025", "dmy")
    assert {:ok, ~D[2025-05-04]} = DateParser.parse("4 Μαΐου 2025", "dmy")
  end

  test "two-digit years pivot at 70" do
    assert {:ok, ~D[2069-01-02]} = DateParser.parse("02/01/69", "dmy")
    assert {:ok, ~D[1970-01-02]} = DateParser.parse("02/01/70", "dmy")
  end

  test "Excel serial dates" do
    assert {:ok, ~D[2025-03-04]} = DateParser.parse("45720", "dmy")
    assert {:ok, ~D[1900-01-01]} = DateParser.parse("2", "mdy")
  end

  test "blank and invalid" do
    assert :blank = DateParser.parse("  ", "dmy")
    assert {:error, :invalid_date} = DateParser.parse("31/02/2025", "dmy")
    assert {:error, :invalid_date} = DateParser.parse("soon", "dmy")
  end

  test "guess_order prefers the default and rules out impossible orders" do
    assert "dmy" = DateParser.guess_order(["01/02/2025", "03/04/2025"], "dmy")
    assert "mdy" = DateParser.guess_order(["12/31/2025", "01/02/2025"], "dmy")
    assert "dmy" = DateParser.guess_order(["31/12/2025"], "mdy")
    assert nil == DateParser.guess_order(["31/12/2025", "12/31/2025"], "dmy")
  end
end
