defmodule Palee.Email.Templates.BusinessActivationLink do
  @moduledoc """
  `:business_activation_link` (ADR-184, ADR-205): the Palee team's
  activation link of a demo business, sent to the verified email of the one
  account it is for, in that account's language.

  Assigns: `name` (the account's display name), `business_name`, `role`
  (`"owner"` | `"admin"`), `url` (the absolute `/activate-business#token=…`).

  The vendor may replace a link (and so send a new email) a few times in a
  row, so the minimum interval is shorter than the account default.
  """

  use Palee.Email.Template, category: :account

  @impl true
  def throttle, do: %{min_interval_seconds: 10, max_per_day: 10}

  @impl true
  def subject(%{business_name: business}, locale),
    do: t(locale, "Activate %{business} on %{product}", %{business: business, product: product()})

  @impl true
  def text(assigns, locale) do
    Layout.text(locale, [
      greeting(assigns, locale),
      intro(assigns, locale),
      role(assigns, locale),
      Layout.text_button(t(locale, "Activate business"), assigns.url),
      notes(locale)
    ])
  end

  @impl true
  def html(assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(t(locale, "Your business is ready to go live")),
        Layout.paragraph(greeting(assigns, locale)),
        Layout.paragraph(intro(assigns, locale)),
        Layout.paragraph(role(assigns, locale)),
        Layout.button(t(locale, "Activate business"), assigns.url),
        Layout.note(notes(locale)),
        Layout.fallback_link(locale, assigns.url)
      ],
      preheader: intro(assigns, locale)
    )
  end

  defp greeting(%{name: name}, locale) when is_binary(name) and name != "",
    do: t(locale, "Hello %{name},", %{name: name})

  defp greeting(_assigns, locale), do: t(locale, "Hello,")

  defp intro(%{business_name: business}, locale),
    do:
      t(
        locale,
        "The %{product} team approved %{business}. Open the link while signed in to your account to activate it: the demo data is removed and the business goes live.",
        %{business: business, product: product()}
      )

  defp role(%{role: "admin"}, locale),
    do: t(locale, "Your role: admin.")

  defp role(_assigns, locale), do: t(locale, "Your role: owner.")

  defp notes(locale) do
    t(locale, "This link works only once.") <>
      " " <> t(locale, "It opens only for your own account.")
  end

  defp product, do: Layout.product_name()
end
