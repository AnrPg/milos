defmodule Palee.Imports.Domain.EncodingTest do
  use ExUnit.Case, async: true

  alias Palee.Imports.Domain.Encoding

  test "UTF-8 with and without a byte order mark" do
    assert {:ok, "Όνομα,Email", "utf8", []} = Encoding.to_utf8("﻿Όνομα,Email")
    assert {:ok, "Name,Email", "utf8", []} = Encoding.to_utf8("Name,Email")
    assert {:ok, "Μαρία", "utf8", []} = Encoding.to_utf8("Μαρία")
  end

  test "UTF-16 little and big endian, with and without a mark" do
    text = "Όνομα;Τηλέφωνο\nΜαρία;6941234567"
    le = :unicode.characters_to_binary(text, :utf8, {:utf16, :little})
    be = :unicode.characters_to_binary(text, :utf8, {:utf16, :big})

    assert {:ok, ^text, "utf16le", []} = Encoding.to_utf8(<<0xFF, 0xFE>> <> le)
    assert {:ok, ^text, "utf16be", []} = Encoding.to_utf8(<<0xFE, 0xFF>> <> be)

    ascii = :unicode.characters_to_binary("Name,Email\nAnna,a@b.co", :utf8, {:utf16, :little})
    assert {:ok, "Name,Email\nAnna,a@b.co", "utf16le", []} = Encoding.to_utf8(ascii)
  end

  test "Windows-1252 for Western text" do
    # "Café; Größe; €5" in Windows-1252
    bytes = <<"Caf", 0xE9, "; Gr", 0xF6, 0xDF, "e; ", 0x80, "5">>
    assert {:ok, "Café; Größe; €5", "windows1252", []} = Encoding.to_utf8(bytes)
  end

  test "Windows-1253 for Greek text (Excel on a Greek Windows)" do
    # "Ά" is A2 in Windows-1253; "Μαρία Άννα"
    bytes = <<0xCC, 0xE1, 0xF1, 0xDF, 0xE1, " ", 0xA2, 0xED, 0xED, 0xE1>>
    assert {:ok, "Μαρία Άννα", "windows1253", []} = Encoding.to_utf8(bytes)
  end

  test "ISO-8859-7 when Ά is B6 and no Windows-only byte appears" do
    bytes = <<0xB6, 0xED, 0xED, 0xE1, " ", 0xCC, 0xE1, 0xF1, 0xDF, 0xE1>>
    assert {:ok, "Άννα Μαρία", "iso88597", []} = Encoding.to_utf8(bytes)
  end

  test "bytes with no character become U+FFFD with a warning" do
    assert {:ok, text, "windows1252", [:undecodable_bytes]} = Encoding.to_utf8(<<"a", 0x81, "b", 0xE9>>)
    assert text == "a�bé"
  end
end
