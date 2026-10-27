defmodule Palee.Email.Templates.ShareLink do
  @moduledoc """
  `:share_link` (ADR-210): a member's share link sent by email, from
  "Send by email" in the share sheet of a guest pass, a check-in buddy
  invite link or «Φέρε φίλο». It carries only the link and the sender's name
  (never a note of theirs) and tells the reader to ignore it if they don't
  know the sender. Rendered in the sender's language.

  Category `:transactional`: a guest pass or «Φέρε φίλο» of a demo business
  is refused by the outbox's demo gate (ADR-184).

  Assigns: `link` (`:guest_pass | :buddy_invite | :referral`), `name` (the
  sender as `ShareLinkPolicy.sender_name/2` shows them), `url`. Strings:
  the `share_links` gettext domain.
  """

  use Palee.Email.Template, category: :transactional

  @domain "share_links"

  # A few a day to one address, from everyone together: enough for real
  # invitations, too few to flood someone.
  @impl true
  def throttle, do: %{max_per_day: 5, min_interval_seconds: 0}

  @impl true
  def subject(%{link: :guest_pass, name: name}, locale),
    do: s(locale, "%{name} invited you to an event", %{name: name})

  def subject(%{link: :buddy_invite, name: name}, locale),
    do: s(locale, "%{name} asked you to be their check-in buddy", %{name: name})

  def subject(%{link: :referral, name: name}, locale),
    do: s(locale, "%{name} invited you to train together", %{name: name})

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(
      locale,
      [
        intro(assigns, locale),
        Layout.text_button(s(locale, "Open the invitation"), url),
        warning(assigns, locale)
      ],
      reason: reason(assigns, locale)
    )
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(intro(assigns, locale)),
        Layout.button(s(locale, "Open the invitation"), url),
        Layout.note(warning(assigns, locale)),
        Layout.fallback_link(locale, url)
      ],
      reason: reason(assigns, locale),
      preheader: intro(assigns, locale)
    )
  end

  defp intro(%{link: :guest_pass, name: name}, locale),
    do:
      s(
        locale,
        "%{name} invited you to an event on %{product} as their guest. Open the invitation to see it and say if you're coming.",
        bindings(name)
      )

  defp intro(%{link: :buddy_invite, name: name}, locale),
    do:
      s(
        locale,
        "%{name} asked you to be their check-in buddy on %{product}: someone they can turn to for support.",
        bindings(name)
      )

  defp intro(%{link: :referral, name: name}, locale),
    do:
      s(
        locale,
        "%{name} invited you to train together on %{product}.",
        bindings(name)
      )

  defp warning(%{name: name}, locale),
    do:
      s(
        locale,
        "%{name} typed in your address to send you this link. If you don't know them, ignore this email.",
        %{name: name}
      )

  defp reason(%{name: name}, locale),
    do:
      s(
        locale,
        "You're receiving this email because %{name} sent you an invitation through %{product}.",
        bindings(name)
      )

  defp bindings(name), do: %{name: name, product: Layout.product_name()}

  defp s(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
