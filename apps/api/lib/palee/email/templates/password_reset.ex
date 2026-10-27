defmodule Palee.Email.Templates.PasswordReset do
  @moduledoc """
  `:password_reset` (ADR-206): the reset link emailed to a login's verified
  address when the person asks for it on "Forgot password". The link opens
  `/reset-password#token=...` and works once, for one hour.

  Assigns: `url` (the link), `name` (the display name, optional).

  Throttle: at most one every 10 minutes and five a day per address, so the
  form cannot be used to flood someone's inbox (the application checks the
  same limits per login).
  """

  use Palee.Email.Template, category: :security

  @impl true
  def throttle, do: %{min_interval_seconds: 600, max_per_day: 5}

  @impl true
  def subject(_assigns, locale),
    do: t(locale, "Reset your %{product} password", %{product: Layout.product_name()})

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(locale, [
      greeting(assigns, locale),
      intro(locale),
      Layout.text_button(t(locale, "Choose a new password"), url),
      lifetime(locale),
      t(locale, "Setting a new password signs you out on every device."),
      ignore(locale)
    ])
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(t(locale, "Reset your password")),
        Layout.paragraph(greeting(assigns, locale)),
        Layout.paragraph(intro(locale)),
        Layout.button(t(locale, "Choose a new password"), url),
        Layout.note(lifetime(locale)),
        Layout.note(t(locale, "Setting a new password signs you out on every device.")),
        Layout.note(ignore(locale)),
        Layout.fallback_link(locale, url)
      ],
      preheader: intro(locale)
    )
  end

  defp greeting(%{name: name}, locale) when is_binary(name) and name != "",
    do: t(locale, "Hello %{name},", %{name: name})

  defp greeting(_assigns, locale), do: t(locale, "Hello,")

  defp intro(locale),
    do:
      t(
        locale,
        "Someone asked to reset the password of your %{product} account. To choose a new password, use the button below.",
        %{product: Layout.product_name()}
      )

  defp lifetime(locale),
    do: t(locale, "This link works for 1 hour.") <> " " <> t(locale, "This link works only once.")

  defp ignore(locale),
    do:
      t(locale, "If you didn't ask for this, you can safely ignore this email.") <>
        " " <> t(locale, "Your password has not been changed.")
end
