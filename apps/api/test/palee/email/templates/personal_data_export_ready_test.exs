defmodule Palee.Email.Templates.PersonalDataExportReadyTest do
  # ADR-267: the "your data is ready" notice, in every locale, with the way
  # to Settings and never a download link.
  use ExUnit.Case, async: true

  alias Palee.Email.Templates
  alias Palee.Email.Templates.PersonalDataExportReady

  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)
  @assigns %{url: "https://palee.test/me/settings#your-data", keep_days: 7}

  test "is a registered account email" do
    assert {:ok, PersonalDataExportReady} = Templates.fetch(:personal_data_export_ready)
    assert PersonalDataExportReady.category() == :account
  end

  test "every locale has every string" do
    msgids =
      Regex.scan(~r/^msgid "(.+)"$/m, File.read!("priv/gettext/personal_data.pot"),
        capture: :all_but_first
      )
      |> List.flatten()

    assert length(msgids) == 5

    for dir <- @locales do
      po = File.read!(Path.join(["priv/gettext", dir, "LC_MESSAGES", "personal_data.po"]))

      for msgid <- msgids do
        assert po =~ ~s(msgid "#{msgid}"\nmsgstr "), "#{dir} lacks #{msgid}"
        refute po =~ ~s(msgid "#{msgid}"\nmsgstr ""\n), "#{dir} leaves #{msgid} untranslated"
      end
    end
  end

  test "Greek and English, with Settings and the days it is kept" do
    assert PersonalDataExportReady.subject(@assigns, "el") ==
             "Τα δεδομένα σου είναι έτοιμα για λήψη"

    text = PersonalDataExportReady.text(@assigns, "el")
    assert text =~ "https://palee.test/me/settings#your-data"
    assert text =~ "7 ημέρες"

    html = PersonalDataExportReady.html(@assigns, "en")
    assert html =~ "Open Settings"
    assert html =~ "kept for 7 days"
  end

  test "renders in every locale" do
    for locale <- ["pt-PT" | @locales -- ["pt_PT"]] do
      assert PersonalDataExportReady.subject(@assigns, locale) != ""
      assert PersonalDataExportReady.text(@assigns, locale) =~ "/me/settings#your-data"
    end
  end
end
