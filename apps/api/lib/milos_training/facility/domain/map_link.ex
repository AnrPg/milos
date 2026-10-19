defmodule MilosTraining.Facility.Domain.MapLink do
  @moduledoc """
  Reads a map point out of a pasted Google Maps link (ADR-141). Long links
  carry the point; short `maps.app.goo.gl` links must be followed first, and
  only hosts listed here may be followed.
  """

  @short_hosts ~w(maps.app.goo.gl goo.gl g.co)
  @long_host ~r/^(www\.|maps\.)?google\.[a-z.]{2,6}$/

  @doc "Whether the text looks like a Google Maps link at all."
  def link?(text) when is_binary(text) do
    case URI.parse(String.trim(text)) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        short_host?(host) or long_host?(host)

      _other ->
        false
    end
  end

  def link?(_text), do: false

  def short_host?(host), do: String.downcase(host) in @short_hosts
  def long_host?(host), do: String.downcase(host) =~ @long_host

  @doc """
  `{:ok, {latitude, longitude}}` from a long link. The exact place
  (`!3d…!4d…`) wins over the camera (`@lat,lng`) and over `q=`/`ll=`.
  """
  def coordinates(url) when is_binary(url) do
    decoded = URI.decode(url)

    [
      ~r/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/,
      ~r/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/,
      ~r/[?&](?:q|query|ll|center|destination)=(-?\d+(?:\.\d+)?),\s*\+?(-?\d+(?:\.\d+)?)/
    ]
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, decoded) do
        [_, lat, lng] -> valid({parse(lat), parse(lng)})
        _none -> nil
      end
    end)
    |> case do
      nil -> {:error, :no_coordinates}
      point -> {:ok, point}
    end
  end

  defp parse(number) do
    {value, ""} = Float.parse(number)
    value
  end

  defp valid({lat, lng} = point) when lat >= -90 and lat <= 90 and lng >= -180 and lng <= 180,
    do: point

  defp valid(_point), do: nil
end
