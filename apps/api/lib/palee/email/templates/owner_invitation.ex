defmodule Palee.Email.Templates.OwnerInvitation do
  @moduledoc """
  `:owner_invitation` (ADR-210): the email the Palee team sends the first
  owner (or an admin) of a business it set up, with the setup link. The link
  is the whole email: the raw invitation code is never in it (the vendor
  console shows it as the manual fallback).

  Category `:account`: the platform's own mail, so it is not demo gated (the
  vendor provisions the business before it goes live).

  Assigns: `business` (its name), `role` (`:owner` or `:admin`), `url` (the
  `/set-admin` link). Strings: the `owner_invitations` gettext domain.
  """

  use Palee.Email.Template, category: :account

  @domain "owner_invitations"

  @impl true
  def subject(%{business: business} = assigns, locale) do
    case role(assigns) do
      :admin -> o(locale, "Set up your admin account for %{business}", %{business: business})
      :owner -> o(locale, "Set up your owner account for %{business}", %{business: business})
    end
  end

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(
      locale,
      [
        o(locale, "Welcome to %{product}", product()),
        intro(assigns, locale),
        Layout.text_button(o(locale, "Set up my account"), url),
        t(locale, "This link works only once.") <> " " <> expired(locale),
        o(locale, "If you weren't expecting this email, you can ignore it.")
      ],
      reason: reason(assigns, locale)
    )
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(o(locale, "Welcome to %{product}", product())),
        Layout.paragraph(intro(assigns, locale)),
        Layout.button(o(locale, "Set up my account"), url),
        Layout.note(t(locale, "This link works only once.") <> " " <> expired(locale)),
        Layout.note(o(locale, "If you weren't expecting this email, you can ignore it.")),
        Layout.fallback_link(locale, url)
      ],
      reason: reason(assigns, locale),
      preheader: intro(assigns, locale)
    )
  end

  defp intro(%{business: business} = assigns, locale) do
    bindings = Map.put(product(), :business, business)

    case role(assigns) do
      :admin ->
        o(
          locale,
          "The %{product} team made you an admin of %{business}. Create your account to get started.",
          bindings
        )

      :owner ->
        o(
          locale,
          "The %{product} team made you the owner of %{business}. Create your account to get started.",
          bindings
        )
    end
  end

  defp expired(locale),
    do: o(locale, "If it has expired, ask the %{product} team for a new invitation.", product())

  defp reason(%{business: business}, locale),
    do:
      o(
        locale,
        "You're receiving this email because the %{product} team set up %{business} with this address.",
        Map.put(product(), :business, business)
      )

  defp role(%{role: role}) when role in [:admin, "admin"], do: :admin
  defp role(_assigns), do: :owner

  defp product, do: %{product: Layout.product_name()}

  defp o(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
