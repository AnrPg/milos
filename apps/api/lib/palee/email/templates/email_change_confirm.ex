defmodule Palee.Email.Templates.EmailChangeConfirm do
  @moduledoc """
  `:email_change_confirm` (ADR-207): the link a login's new address gets to
  confirm an email change. It never names the account or its current
  address: whoever reads this inbox learns nothing about the account.

  Assigns: `url` (the `/confirm-email-change#token=...` link).
  """

  use Palee.Email.Template, category: :security

  @impl true
  def subject(_assigns, locale), do: t(locale, "Confirm your new email address")

  @impl true
  def text(%{url: url}, locale) do
    Layout.text(
      locale,
      [
        t(locale, "Hello,"),
        body(locale),
        Layout.text_button(t(locale, "Confirm this address"), url),
        notes(locale)
      ],
      reason: reason(locale)
    )
  end

  @impl true
  def html(%{url: url}, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(t(locale, "Confirm your new email address")),
        Layout.paragraph(t(locale, "Hello,")),
        Layout.paragraph(body(locale)),
        Layout.button(t(locale, "Confirm this address"), url),
        Layout.fallback_link(locale, url),
        Layout.note(notes(locale))
      ],
      reason: reason(locale),
      preheader: body(locale)
    )
  end

  defp body(locale),
    do:
      t(
        locale,
        "Someone asked to make this the sign-in address of a %{product} account. Confirm it to finish the change. Until then, the account keeps its current address.",
        %{product: Layout.product_name()}
      )

  defp notes(locale) do
    Enum.join(
      [
        t(locale, "The link works for 24 hours."),
        t(locale, "This link works only once."),
        t(locale, "If you didn't ask for this, you can safely ignore this email.")
      ],
      " "
    )
  end

  defp reason(locale),
    do:
      t(
        locale,
        "You're receiving this email because someone asked to use this address for a %{product} account.",
        %{product: Layout.product_name()}
      )
end
