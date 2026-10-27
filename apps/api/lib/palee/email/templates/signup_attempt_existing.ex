defmodule Palee.Email.Templates.SignupAttemptExisting do
  @moduledoc """
  `:signup_attempt_existing` (ADR-211): someone tried to sign up with an
  email that already has a login, without its password. The sign-up form
  answered as for a new account, so this email is the only place the
  address's owner hears of it. It carries no token: both links open public
  pages (sign in, forgot password).

  Assigns: `sign_in_url`, `reset_url`. Strings live in the
  `account_lifecycle` gettext domain.
  """

  use Palee.Email.Template, category: :account

  @domain "account_lifecycle"

  # At most one an hour and three a day per address: enough for someone who
  # forgot they already signed up, too few to flood a stranger's inbox.
  @impl true
  def throttle, do: %{min_interval_seconds: 3_600, max_per_day: 3}

  @impl true
  def subject(_assigns, locale), do: tr(locale, "Someone tried to sign up with your email")

  @impl true
  def text(%{sign_in_url: sign_in_url, reset_url: reset_url}, locale) do
    Layout.text(locale, [
      Layout.t(locale, "Hello,"),
      intro(locale),
      tr(
        locale,
        "If it was you, sign in to add a profile, or reset your password if you forgot it."
      ),
      Layout.text_button(tr(locale, "Sign in"), sign_in_url),
      Layout.text_button(tr(locale, "Reset password"), reset_url),
      tr(
        locale,
        "If it wasn't you, you can ignore this email. No account was created and nothing changed."
      )
    ])
  end

  @impl true
  def html(%{sign_in_url: sign_in_url, reset_url: reset_url}, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(tr(locale, "Someone tried to sign up with your email")),
        Layout.paragraph(Layout.t(locale, "Hello,")),
        Layout.paragraph(intro(locale)),
        Layout.paragraph(
          tr(
            locale,
            "If it was you, sign in to add a profile, or reset your password if you forgot it."
          )
        ),
        Layout.button(tr(locale, "Sign in"), sign_in_url),
        Layout.paragraph(tr(locale, "Forgot your password?")),
        Layout.button(tr(locale, "Reset password"), reset_url),
        Layout.note(
          tr(
            locale,
            "If it wasn't you, you can ignore this email. No account was created and nothing changed."
          )
        )
      ],
      preheader: intro(locale)
    )
  end

  defp intro(locale),
    do:
      tr(locale, "Someone tried to create a %{product} account with this email address.", %{
        product: Layout.product_name()
      })

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
