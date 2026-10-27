defmodule Palee.Email.Templates.OrganizationInvitation do
  @moduledoc """
  `:organization_invitation` (ADR-209): a box invites a client or a staff
  member by email. The strings live in their own gettext domain,
  `invitation_emails`, in every API locale.

  Assigns:

    * `business` - the box's name (its brand name when it has one);
    * `inviter` - the inviter's display name, or nil;
    * `roles` - the role set (atoms or strings);
    * `branches` - staff only: `:all` or the branch names; nil for clients;
    * `expires` - when the link stops working, already formatted in the
      box's time zone;
    * `url` - the link (the invitation token is in its fragment).

  Category `transactional`: it is the box's mail, so a box in demo mode
  sends none (ADR-184). One address gets at most 5 a day, 2 minutes apart.
  """

  use Palee.Email.Template, category: :transactional

  alias Palee.Localization

  @domain "invitation_emails"

  @role_labels %{
    "owner" => "Owner",
    "admin" => "Admin",
    "coach" => "Coach",
    "front_desk" => "Front desk",
    "accountant" => "Accountant",
    "janitor" => "Cleaning staff",
    "member" => "Box member",
    "athlete" => "Athlete"
  }

  @impl true
  def throttle, do: %{min_interval_seconds: 120, max_per_day: 5}

  @doc "Every msgid of the domain (the locale test checks each one is translated)."
  def msgids do
    Map.values(@role_labels) ++
      [
        "Your invitation to %{business}",
        "You're invited to %{business}",
        "%{inviter} invited you to join %{business} on %{product}.",
        "%{business} invited you to join on %{product}.",
        "Accept the invitation",
        "Joins as",
        "Branches",
        "All branches",
        "The link works once and expires on %{date}.",
        "Create your account or sign in with this email address to accept.",
        "If you weren't expecting this invitation, you can ignore this email."
      ]
  end

  @impl true
  def subject(assigns, locale),
    do: tr(locale, "Your invitation to %{business}", %{business: assigns.business})

  @impl true
  def text(assigns, locale) do
    copy = copy(assigns, locale)

    Layout.text(
      locale,
      [
        copy.heading,
        copy.intro,
        Layout.text_details(copy.rows),
        copy.how,
        Layout.text_button(copy.cta, assigns.url),
        copy.expiry,
        copy.ignore
      ],
      reason: copy.reason
    )
  end

  @impl true
  def html(assigns, locale) do
    copy = copy(assigns, locale)

    Layout.html(
      locale,
      [
        Layout.heading(copy.heading),
        Layout.paragraph(copy.intro),
        Layout.details(copy.rows),
        Layout.paragraph(copy.how),
        Layout.button(copy.cta, assigns.url),
        Layout.fallback_link(locale, assigns.url),
        Layout.note(copy.expiry),
        Layout.note(copy.ignore)
      ],
      reason: copy.reason,
      preheader: copy.intro
    )
  end

  defp copy(assigns, locale) do
    business = assigns.business
    product = Layout.product_name()

    intro =
      case Map.get(assigns, :inviter) do
        name when is_binary(name) and name != "" ->
          tr(locale, "%{inviter} invited you to join %{business} on %{product}.", %{
            inviter: name,
            business: business,
            product: product
          })

        _none ->
          tr(locale, "%{business} invited you to join on %{product}.", %{
            business: business,
            product: product
          })
      end

    %{
      heading: tr(locale, "You're invited to %{business}", %{business: business}),
      intro: intro,
      rows: rows(assigns, locale),
      how: tr(locale, "Create your account or sign in with this email address to accept."),
      cta: tr(locale, "Accept the invitation"),
      expiry: tr(locale, "The link works once and expires on %{date}.", %{date: assigns.expires}),
      ignore: tr(locale, "If you weren't expecting this invitation, you can ignore this email."),
      reason: Layout.reason(locale, {:business, business})
    }
  end

  defp rows(assigns, locale) do
    roles =
      assigns.roles
      |> Enum.map(&to_string/1)
      |> Enum.map_join(", ", &tr(locale, Map.get(@role_labels, &1, &1)))

    [{tr(locale, "Joins as"), roles}] ++ branch_rows(Map.get(assigns, :branches), locale)
  end

  defp branch_rows(:all, locale), do: [{tr(locale, "Branches"), tr(locale, "All branches")}]

  defp branch_rows([_ | _] = names, locale),
    do: [{tr(locale, "Branches"), Enum.join(names, ", ")}]

  defp branch_rows(_clients, _locale), do: []

  defp tr(locale, msgid, bindings \\ %{}),
    do: Localization.translate(locale, msgid, bindings, @domain)
end
