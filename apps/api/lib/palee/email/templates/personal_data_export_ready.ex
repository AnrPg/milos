defmodule Palee.Email.Templates.PersonalDataExportReady do
  @moduledoc """
  `:personal_data_export_ready` (ADR-267): the copy of the person's data
  they asked for is ready. The email carries no download link, only the way
  to Settings, where the signed-in person gets a short-lived one.

  Assigns: `url` (Settings), `keep_days`. Strings live in the
  `personal_data` gettext domain.
  """

  use Palee.Email.Template, category: :account

  @domain "personal_data"

  @impl true
  def subject(_assigns, locale), do: tr(locale, "Your data is ready to download")

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(locale, [
      Layout.t(locale, "Hello,"),
      what(locale),
      where(assigns, locale),
      Layout.text_button(tr(locale, "Open Settings"), url),
      not_you(locale)
    ])
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(tr(locale, "Your data is ready to download")),
        Layout.paragraph(Layout.t(locale, "Hello,")),
        Layout.paragraph(what(locale)),
        Layout.paragraph(where(assigns, locale)),
        Layout.button(tr(locale, "Open Settings"), url),
        Layout.fallback_link(locale, url),
        Layout.note(not_you(locale))
      ],
      preheader: what(locale)
    )
  end

  defp what(locale),
    do:
      tr(
        locale,
        "The copy of your data you asked for is ready: one ZIP file with your profile, bookings, journal, wellness, devices, the messages you wrote, payments, receipts and signed documents."
      )

  defp where(%{keep_days: days}, locale),
    do:
      tr(
        locale,
        "Download it from Settings while you are signed in. It is kept for %{days} days.",
        %{days: days}
      )

  defp not_you(locale),
    do:
      tr(
        locale,
        "If you didn't ask for this, change your password: someone else may know it."
      )

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
