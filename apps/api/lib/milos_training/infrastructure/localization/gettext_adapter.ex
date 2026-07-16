defmodule MilosTraining.Infrastructure.Localization.GettextAdapter do
  @moduledoc false

  alias MilosTraining.Infrastructure.Localization.GettextBackend

  def translate(locale, domain, message, bindings) do
    gettext_locale = if locale == "pt-PT", do: "pt_PT", else: locale || "en"

    Gettext.with_locale(GettextBackend, gettext_locale, fn ->
      Gettext.dgettext(GettextBackend, domain, message, bindings)
    end)
  end
end
