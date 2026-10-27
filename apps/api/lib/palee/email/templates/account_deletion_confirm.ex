defmodule Palee.Email.Templates.AccountDeletionConfirm do
  @moduledoc """
  `:account_deletion_confirm` (ADR-211): the link that confirms a
  self-service deletion the person asked for with their password. Opening it
  schedules the deletion after the grace days; it can still be undone then.

  Assigns: `scope` (`:profile` | `:login`), `handle` (the profile's), `url`
  (the confirmation link, token in the fragment), `grace_days`. Strings
  live in the `account_lifecycle` gettext domain.
  """

  use Palee.Email.Template, category: :security

  @domain "account_lifecycle"

  @impl true
  def subject(assigns, locale), do: title(assigns, locale)

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(locale, [
      Layout.t(locale, "Hello,"),
      what(assigns, locale),
      when_(assigns, locale),
      Layout.text_button(tr(locale, "Confirm deletion"), url),
      tr(locale, "The link expires in 24 hours.") <>
        " " <> Layout.t(locale, "This link works only once."),
      not_you(locale)
    ])
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(title(assigns, locale)),
        Layout.paragraph(Layout.t(locale, "Hello,")),
        Layout.paragraph(what(assigns, locale)),
        Layout.paragraph(when_(assigns, locale)),
        Layout.button(tr(locale, "Confirm deletion"), url),
        Layout.fallback_link(locale, url),
        Layout.note(
          tr(locale, "The link expires in 24 hours.") <>
            " " <> Layout.t(locale, "This link works only once.")
        ),
        Layout.note(not_you(locale))
      ],
      preheader: what(assigns, locale)
    )
  end

  defp title(%{scope: :profile}, locale), do: tr(locale, "Confirm deleting your profile")
  defp title(_assigns, locale), do: tr(locale, "Confirm deleting your account")

  defp what(%{scope: :profile, handle: handle}, locale) when is_binary(handle),
    do: tr(locale, "You asked to delete your profile @%{handle}.", %{handle: handle})

  defp what(_assigns, locale),
    do: tr(locale, "You asked to delete your account with all its profiles.")

  defp when_(%{grace_days: days}, locale),
    do:
      tr(
        locale,
        "After you confirm, the deletion takes place in %{days} days. Until then you can undo it.",
        %{days: days}
      )

  defp not_you(locale),
    do:
      tr(
        locale,
        "If you didn't ask for this, don't open the link and change your password: someone else knows it."
      )

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
