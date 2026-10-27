defmodule Palee.Email.Templates.VerifyEmail do
  @moduledoc """
  `:verify_email` (ADR-213): the link that confirms a login's email address,
  sent when a new login is created and again on request. The link carries
  its token in the fragment (`/verify-email#token=...`) so mail scanners and
  server logs never see it; the page posts it.

  Assigns: `name` (the display name, optional), `email`, `url`.
  """

  use Palee.Email.Template, category: :account

  @impl true
  def throttle, do: %{min_interval_seconds: 60, max_per_day: 5}

  @impl true
  def subject(_assigns, locale), do: t(locale, "Confirm your email address")

  @impl true
  def text(assigns, locale) do
    Layout.text(locale, [
      greeting(assigns, locale),
      body(assigns, locale),
      Layout.text_button(t(locale, "Confirm email"), assigns.url),
      lifetime(locale),
      ignore(locale)
    ])
  end

  @impl true
  def html(assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(t(locale, "Confirm your email address")),
        Layout.paragraph(greeting(assigns, locale)),
        Layout.paragraph(body(assigns, locale)),
        Layout.button(t(locale, "Confirm email"), assigns.url),
        Layout.note(lifetime(locale)),
        Layout.note(ignore(locale)),
        Layout.fallback_link(locale, assigns.url)
      ],
      preheader: body(assigns, locale)
    )
  end

  defp greeting(%{name: name}, locale) when is_binary(name) and name != "",
    do: t(locale, "Hello %{name},", %{name: name})

  defp greeting(_assigns, locale), do: t(locale, "Hello,")

  defp body(%{email: email}, locale),
    do:
      t(
        locale,
        "Please confirm that %{email} is your email address. It lets you get back into your account if you ever forget your password.",
        %{email: email}
      )

  defp lifetime(locale),
    do:
      t(locale, "This link expires in 48 hours.") <>
        " " <> t(locale, "This link works only once.")

  defp ignore(locale),
    do:
      t(locale, "If you didn't create a %{product} account, you can ignore this email.", %{
        product: Layout.product_name()
      })
end
