defmodule Palee.Email.Templates.SecurityNotice do
  @moduledoc """
  The shared body of every security notice (ADR-208): what happened, when,
  from which device and network, and what to do if it wasn't the reader.
  Each event has its own template module (`Palee.Email.Templates.Security*`,
  kind `:security_<event>`) that `use`s this one, so the registry, throttle
  and delivery status stay per event.

  Assigns (all optional, built by `Palee.Application.SecurityNotices`):
  `name`, `at` (the moment, already on the reader's clock), `device`
  (`%{client:, platform:}` or a string), `ip` (already coarse), `place`,
  `sign_out_url`, `reset_url`, `settings_url`, `revert_url`, `undo_url`,
  `remaining`, `email`, `profile`, `scope` (`:profile | :login`), `date`.
  Never a password, a token other than inside a link, or a recovery code.
  """

  alias Palee.BrandPalette
  alias Palee.Email.Layout

  defmacro __using__(opts) do
    event = Keyword.fetch!(opts, :event)
    throttle = Keyword.get(opts, :throttle)

    quote do
      use Palee.Email.Template, category: :security

      alias Palee.Email.Templates.SecurityNotice

      @impl true
      def subject(assigns, locale), do: SecurityNotice.subject(unquote(event), assigns, locale)

      @impl true
      def text(assigns, locale), do: SecurityNotice.text(unquote(event), assigns, locale)

      @impl true
      def html(assigns, locale), do: SecurityNotice.html(unquote(event), assigns, locale)

      if unquote(throttle) do
        @impl true
        def throttle, do: unquote(throttle)
      end
    end
  end

  # -- rendering ---------------------------------------------------------------

  @doc "The subject line of an event's notice."
  def subject(event, assigns, locale), do: content(event, assigns, locale).title

  @doc "The HTML body."
  def html(event, assigns, locale) do
    c = content(event, assigns, locale)

    blocks = [
      Layout.heading(c.title),
      greeting(assigns, locale) |> Layout.paragraph(),
      Enum.map(c.lines, &Layout.paragraph/1),
      details_html(assigns, locale),
      Enum.map(c.advice, &Layout.paragraph/1),
      action_html(c.action, locale),
      secondary_html(c.secondary),
      Enum.map(c.notes, &Layout.note/1)
    ]

    Layout.html(locale, blocks, reason: reason(locale), preheader: List.first(c.lines))
  end

  @doc "The plain-text body."
  def text(event, assigns, locale) do
    c = content(event, assigns, locale)

    blocks = [
      greeting(assigns, locale),
      c.lines,
      details_text(assigns, locale),
      c.advice,
      text_link(c.action),
      text_link(c.secondary),
      c.notes
    ]

    Layout.text(locale, blocks, reason: reason(locale))
  end

  @doc "The footer line: why the reader gets this, and that it can't be turned off."
  def reason(locale),
    do:
      Layout.t(
        locale,
        "You're receiving this security notice because it concerns your %{product} account. Security notices can't be turned off.",
        %{product: Layout.product_name()}
      )

  @doc "A device in words: \"Chrome on Windows\", \"Palee app on iPhone\" (nil when unknown)."
  def device(%{} = device, locale) do
    client = device[:client] || device["client"]
    platform = device[:platform] || device["platform"]
    product = Layout.product_name()

    case {client, platform} do
      {nil, nil} ->
        nil

      {"app", nil} ->
        t(locale, "%{product} app", %{product: product})

      {"app", platform} ->
        t(locale, "%{product} app on %{platform}", %{product: product, platform: platform})

      {nil, platform} ->
        platform

      {client, nil} ->
        client

      {client, platform} ->
        t(locale, "%{client} on %{platform}", %{client: client, platform: platform})
    end
  end

  def device(device, _locale) when is_binary(device) and device != "", do: device
  def device(_device, _locale), do: nil

  # -- content per event -------------------------------------------------------

  defp content(event, a, locale) do
    product = Layout.product_name()
    p = %{product: product}
    base = %{title: nil, lines: [], advice: [], action: nil, secondary: nil, notes: []}

    event
    |> event_content(a, locale, p)
    |> then(&Map.merge(base, &1))
  end

  defp event_content(:password_changed, a, l, p) do
    %{
      title: t(l, "Your password was changed"),
      lines: [t(l, "The password of your %{product} account was changed in Settings.", p)]
    }
    |> not_you(a, l)
  end

  defp event_content(:password_reset_completed, a, l, p) do
    %{
      title: t(l, "Your password was reset"),
      lines: [
        t(
          l,
          "The password of your %{product} account was reset, and every device was signed out.",
          p
        )
      ]
    }
    |> not_you(a, l)
  end

  defp event_content(:email_change_requested, a, l, p) do
    line =
      if present?(a[:email]),
        do:
          t(
            l,
            "Someone signed in to your %{product} account asked to change its email address to %{email}. Nothing changes until the new address is confirmed.",
            Map.put(p, :email, a[:email])
          ),
        else:
          t(
            l,
            "Someone signed in to your %{product} account asked to change its email address. Nothing changes until the new address is confirmed.",
            p
          )

    %{title: t(l, "A change of your email address was requested"), lines: [line]}
    |> not_you(a, l)
  end

  defp event_content(:email_changed, a, l, p) do
    line =
      if present?(a[:email]),
        do:
          t(
            l,
            "The email address of your %{product} account was changed to %{email}. Emails about your account now go there.",
            Map.put(p, :email, a[:email])
          ),
        else:
          t(
            l,
            "The email address of your %{product} account was changed. Emails about your account now go to the new address.",
            p
          )

    content = %{title: t(l, "Your email address was changed"), lines: [line]}

    if present?(a[:revert_url]) do
      Map.merge(content, %{
        advice: [
          t(l, "If this was you, there's nothing else to do."),
          t(
            l,
            "If this wasn't you, undo the change right away. Then sign out everywhere and choose a new password."
          )
        ],
        action: {t(l, "Undo this change"), a[:revert_url]},
        secondary: sign_out_link(a, l)
      })
    else
      not_you(content, a, l)
    end
  end

  defp event_content(:recovery_code_used, a, l, p) do
    %{
      title: t(l, "A recovery code was used"),
      lines: [
        t(
          l,
          "One of your recovery codes was used to set a new password for your %{product} account, and every device was signed out.",
          p
        )
      ]
    }
    |> not_you(a, l)
  end

  defp event_content(:recovery_codes_regenerated, a, l, p) do
    %{
      title: t(l, "New recovery codes were created"),
      lines: [
        t(
          l,
          "New recovery codes were created for your %{product} account. The old codes no longer work.",
          p
        )
      ]
    }
    |> not_you(a, l)
  end

  defp event_content(:recovery_codes_running_low, a, l, _p) do
    left =
      case a[:remaining] do
        0 -> t(l, "You have no unused recovery codes left.")
        1 -> t(l, "You have only one unused recovery code left.")
        _two -> t(l, "You have only two unused recovery codes left.")
      end

    %{
      title: t(l, "You're running out of recovery codes"),
      lines: [
        left,
        t(
          l,
          "Create new codes in Settings and keep them somewhere safe, so you can always get back into your account."
        )
      ],
      action: a[:settings_url] && {t(l, "Open Settings"), a[:settings_url]}
    }
  end

  defp event_content(:signed_out_everywhere, a, l, p) do
    %{
      title: t(l, "You were signed out everywhere"),
      lines: [t(l, "Every device signed in to your %{product} account was signed out.", p)],
      advice: [
        t(l, "If this was you, there's nothing else to do."),
        t(l, "If this wasn't you, choose a new password right away.")
      ],
      action: a[:reset_url] && {t(l, "Choose a new password"), a[:reset_url]}
    }
  end

  defp event_content(:profile_added, a, l, p) do
    line =
      if present?(a[:profile]),
        do:
          t(
            l,
            "A new profile was added to your %{product} account: %{profile}.",
            Map.put(p, :profile, a[:profile])
          ),
        else: t(l, "A new profile was added to your %{product} account.", p)

    %{title: t(l, "A profile was added to your account"), lines: [line]}
    |> not_you(a, l)
  end

  defp event_content(:new_sign_in, a, l, p) do
    %{
      title: t(l, "New sign-in to your account"),
      lines: [
        t(
          l,
          "Your %{product} account was just used to sign in on a device it hasn't been used on before.",
          p
        )
      ]
    }
    |> not_you(a, l)
  end

  defp event_content(:account_deletion_scheduled, a, l, p) do
    {title, line} =
      if a[:scope] == :profile,
        do:
          {t(l, "Your profile will be deleted"),
           t(
             l,
             "Your profile %{profile} on %{product} will be deleted on %{date}.",
             deletion_bindings(a, p)
           )},
        else:
          {t(l, "Your account will be deleted"),
           t(
             l,
             "Your %{product} account and all its profiles will be deleted on %{date}.",
             deletion_bindings(a, p)
           )}

    %{
      title: title,
      lines: [line, t(l, "Changed your mind? You can undo it until then.")],
      advice: [
        t(
          l,
          "If this wasn't you, undo the deletion right away. Then sign out everywhere and choose a new password."
        )
      ],
      action: a[:undo_url] && {t(l, "Undo the deletion"), a[:undo_url]},
      secondary: sign_out_link(a, l)
    }
  end

  defp event_content(:account_deleted, a, l, p) do
    {title, line} =
      if a[:scope] == :profile,
        do:
          {t(l, "Your profile was deleted"),
           t(
             l,
             "Your profile %{profile} on %{product} was deleted, as you asked.",
             deletion_bindings(a, p)
           )},
        else:
          {t(l, "Your account was deleted"),
           t(l, "Your %{product} account and all its profiles were deleted, as you asked.", p)}

    %{title: title, lines: [line]}
  end

  defp deletion_bindings(a, p),
    do: Map.merge(p, %{profile: a[:profile] || "", date: a[:date] || ""})

  # "If this wasn't you": sign out everywhere first (a stolen session dies
  # with it), then choose a new password.
  defp not_you(content, a, l) do
    Map.merge(content, %{
      advice: [
        t(l, "If this was you, there's nothing else to do."),
        t(l, "If this wasn't you, sign out everywhere right away, then choose a new password.")
      ],
      action: a[:sign_out_url] && {t(l, "Sign out everywhere"), a[:sign_out_url]},
      secondary: a[:reset_url] && {t(l, "Choose a new password"), a[:reset_url]},
      notes:
        if(a[:sign_out_url],
          do: [
            t(
              l,
              "The sign-out link signs out every device, including this one, and works for 7 days."
            )
          ],
          else: []
        )
    })
  end

  defp sign_out_link(a, l),
    do: a[:sign_out_url] && {t(l, "Sign out everywhere"), a[:sign_out_url]}

  # -- pieces ------------------------------------------------------------------

  defp greeting(a, locale) do
    if present?(a[:name]),
      do: t(locale, "Hello %{name},", %{name: a[:name]}),
      else: t(locale, "Hello,")
  end

  defp detail_rows(a, l) do
    [
      {t(l, "When"), a[:at]},
      {t(l, "Device"), device(a[:device], l)},
      {t(l, "Location"), a[:place]},
      {t(l, "IP address"), a[:ip]}
    ]
    |> Enum.filter(fn {_label, value} -> present?(value) end)
  end

  defp details_html(a, l) do
    case detail_rows(a, l) do
      [] -> ""
      rows -> Layout.details(rows)
    end
  end

  defp details_text(a, l) do
    case detail_rows(a, l) do
      [] -> nil
      rows -> Layout.text_details(rows)
    end
  end

  defp action_html(nil, _locale), do: ""

  defp action_html({label, url}, locale),
    do: [Layout.button(label, url), Layout.fallback_link(locale, url)]

  defp secondary_html(nil), do: ""

  defp secondary_html({label, url}),
    do:
      ~s(<p style="margin:16px 0 0;"><a href="#{Layout.escape(url)}" style="color:#{BrandPalette.colour(:deep)};font-weight:600;">) <>
        Layout.escape(label) <> "</a></p>\n"

  defp text_link(nil), do: nil
  defp text_link({label, url}), do: Layout.text_button(label, url)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp t(locale, message, bindings \\ %{}), do: Layout.t(locale, message, bindings)
end
