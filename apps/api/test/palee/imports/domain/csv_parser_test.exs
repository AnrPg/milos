defmodule Palee.Imports.Domain.CsvParserTest do
  use ExUnit.Case, async: true

  alias Palee.Imports.Domain.CsvParser

  test "comma, semicolon and tab are detected" do
    assert {:ok, %{delimiter: ",", header: ["a", "b"], rows: [["1", "2"]]}} =
             CsvParser.parse("a,b\n1,2\n")

    assert {:ok, %{delimiter: ";", rows: [["1,5", "2"]]}} = CsvParser.parse("a;b\r\n1,5;2\r\n")
    assert {:ok, %{delimiter: "\t", rows: [["x y", "z"]]}} = CsvParser.parse("a\tb\nx y\tz")
  end

  test "an Excel sep= line names the delimiter" do
    assert {:ok, %{delimiter: ";", header: ["a", "b,c"]}} = CsvParser.parse("sep=;\na;b,c\n1;2")
  end

  test "quoted fields keep delimiters, line breaks and doubled quotes" do
    csv = ~s(name,note\n"Papadopoulou, Maria","said ""hi""\nthen left"\n)

    assert {:ok, %{rows: [["Papadopoulou, Maria", "said \"hi\"\nthen left"]]}} =
             CsvParser.parse(csv)
  end

  test "empty lines are dropped, short rows padded, cells trimmed" do
    assert {:ok, %{rows: [["1", ""], ["3", "4"]]}} = CsvParser.parse("a,b\n\n 1 \n,\n3,4\n")
  end

  test "errors" do
    assert {:error, :empty_file} = CsvParser.parse("\n\n")
    assert {:error, :unbalanced_quotes} = CsvParser.parse(~s(a,b\n"open,2\n))
  end
end
