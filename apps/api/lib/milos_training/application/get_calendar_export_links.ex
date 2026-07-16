defmodule MilosTraining.Application.GetCalendarExportLinks do
  alias MilosTraining.Application.{CalendarFeedToken, PublicURL}
  alias MilosTraining.Identity
  alias MilosTraining.Localization

  def call(user, opts \\ []) do
    with {:ok, user} <- maybe_regenerate(user, Keyword.get(opts, :regenerate, false)) do
      {:ok, build_links(user)}
    end
  end

  defp maybe_regenerate(user, true), do: Identity.regenerate_calendar_feed_token(user)
  defp maybe_regenerate(user, false), do: {:ok, user}

  defp build_links(user) do
    locale = user.preferred_locale || "en"
    token = CalendarFeedToken.sign(user)
    path = "/api/calendar/feed.ics?token=#{URI.encode_www_form(token)}"
    https_url = PublicURL.base_url() <> path
    webcal_url = String.replace_prefix(https_url, "https://", "webcal://")
    webcal_url = String.replace_prefix(webcal_url, "http://", "webcal://")

    %{
      token: token,
      path: path,
      https_url: https_url,
      webcal_url: webcal_url,
      download_url: https_url <> "&download=1",
      help: %{
        google:
          translate(
            locale,
            "Google Calendar: copy the HTTPS .ics URL, then use Other calendars → From URL."
          ),
        apple:
          translate(
            locale,
            "Apple Calendar: use Subscribe with the webcal:// link for automatic updates."
          ),
        outlook:
          translate(
            locale,
            "Outlook: use Add calendar → Subscribe from web and paste the HTTPS .ics URL."
          ),
        download:
          translate(
            locale,
            "Downloading the .ics file imports a one-off snapshot and will not stay synchronized."
          )
      }
    }
  end

  defp translate(locale, message), do: Localization.translate(locale, message, %{}, "calendar")
end
