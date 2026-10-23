defmodule Palee.Identity.Domain.HandleAndNamesTest do
  use ExUnit.Case, async: true

  alias Palee.Identity.Domain.{DisplayName, Handle, NameSearch, ProfilePolicy}

  describe "Handle" do
    test "folds case, accents, @ and Greek/Cyrillic to lowercase ASCII" do
      assert Handle.normalize("@Τολάρας") == "tolaras"
      assert Handle.normalize("Anna.K") == "anna.k"
      assert Handle.normalize("Иван_99") == "ivan_99"
    end

    test "accepts letters with a Latin form, digits, dots and underscores" do
      assert Handle.valid?("Τολάρας")
      assert Handle.valid?("anna.k_99")
      refute Handle.valid?("ab")
      refute Handle.valid?(".anna")
      refute Handle.valid?("anna.")
      refute Handle.valid?("an..na")
      refute Handle.valid?("anna k")
      refute Handle.valid?("anna💪")
      # No Latin form: a Chinese name cannot silently become another handle.
      refute Handle.valid?("小明明")
      refute Handle.valid?("ann小a")
      refute Handle.valid?(String.duplicate("a", 31))
    end

    test "suggests a handle from a display name, or nil without a Latin form" do
      assert Handle.suggest("Άννα Μαρία") == "anna_maria"
      assert Handle.suggest("  Jean-Luc  ") == "jean_luc"
      assert Handle.suggest("小明") == nil
      assert Handle.suggest("Al") == nil
    end

    test "alternatives are well-formed and distinct" do
      alternatives = Handle.alternatives("tolaras", 3)
      assert length(alternatives) == 3
      assert Enum.all?(alternatives, &Handle.well_formed?/1)
      assert alternatives == Enum.uniq(alternatives)
    end
  end

  describe "DisplayName" do
    test "keeps any script, emoji and capitals, trims and collapses spaces" do
      assert DisplayName.normalize("  Τολάρας   💪 ") == "Τολάρας 💪"
      assert DisplayName.valid?("小明")
      assert DisplayName.valid?("محمد")
      assert DisplayName.valid?("Anna 💃")
    end

    test "refuses empty, overlong, control and bidi-override names" do
      refute DisplayName.valid?("   ")
      refute DisplayName.valid?(String.duplicate("a", 51))
      refute DisplayName.valid?("ann\u0000a")
      refute DisplayName.valid?("anna\u202Eevil")
      refute DisplayName.valid?("an\u200Bna")
    end
  end

  describe "NameSearch" do
    test "a display name is found in its own script, its Latin form and by handle" do
      key = NameSearch.key("Τολάρας", "tolaras_fit")
      person = %{handle: "tolaras_fit", search_text: key}

      assert NameSearch.matches?(person, "Tolaras")
      assert NameSearch.matches?(person, "τολαρας")
      assert NameSearch.matches?(person, "ΤΟΛΆΡΑΣ")
      assert NameSearch.matches?(person, "@tolaras_f")
      refute NameSearch.matches?(person, "maria")
    end

    test "a name without a transliteration table is found in its own script" do
      person = %{handle: "ming", search_text: NameSearch.key("小明", "ming")}
      assert NameSearch.matches?(person, "小明")
      assert NameSearch.matches?(person, "ming")
    end
  end

  describe "ProfilePolicy" do
    test "three profiles per login" do
      assert ProfilePolicy.can_add_profile?(2)
      refute ProfilePolicy.can_add_profile?(3)
    end

    test "handle changes wait 14 days" do
      now = ~U[2026-10-23 10:00:00Z]
      assert ProfilePolicy.next_handle_change(nil, now) == :now
      assert ProfilePolicy.next_handle_change(~U[2026-10-01 10:00:00Z], now) == :now

      assert ProfilePolicy.next_handle_change(~U[2026-10-20 10:00:00Z], now) ==
               ~U[2026-11-03 10:00:00Z]
    end
  end
end
