defmodule MilosTraining.Identity.Domain.LocaleTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Identity.Domain.Locale
  alias MilosTraining.Identity.User

  test "publishes the complete supported locale set in stable selector order" do
    assert Locale.supported() == [
             "en",
             "el",
             "ar",
             "ru",
             "de",
             "es",
             "pt-PT",
             "he",
             "it",
             "bg",
             "nl",
             "fr"
           ]
  end

  test "normalizes supported locale tags and falls back from regional variants" do
    assert Locale.normalize("EL") == {:ok, "el"}
    assert Locale.normalize("pt-pt") == {:ok, "pt-PT"}
    assert Locale.normalize("de-DE") == {:ok, "de"}
    assert Locale.normalize("pt-BR") == {:error, :unsupported_locale}
  end

  test "rejects missing and unknown locales" do
    assert Locale.normalize(nil) == {:error, :unsupported_locale}
    assert Locale.normalize("") == {:error, :unsupported_locale}
    assert Locale.normalize("ja") == {:error, :unsupported_locale}
  end

  test "marks Arabic and Hebrew as right-to-left" do
    assert Locale.direction("ar") == :rtl
    assert Locale.direction("he") == :rtl
    assert Locale.direction("en") == :ltr
    assert Locale.direction("el") == :ltr
  end

  test "profile changesets accept only canonical supported preferences" do
    assert %{valid?: true} = User.profile_changeset(%User{}, %{"preferred_locale" => "ar"})

    changeset = User.profile_changeset(%User{}, %{"preferred_locale" => "pt-BR"})

    refute changeset.valid?
    assert {"is not supported", _metadata} = changeset.errors[:preferred_locale]
  end
end
