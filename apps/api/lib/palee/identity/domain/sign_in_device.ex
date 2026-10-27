defmodule Palee.Identity.Domain.SignInDevice do
  @moduledoc """
  ADR-208: what Palee keeps about the devices a login signs in from, so a
  sign-in from a device never seen before can be told to the person.

  A device is named by a long-lived random id the web app (and the native
  shell around it) keeps, sent as the `x-palee-device-id` header or the
  `palee_device` cookie. Only a hash of that id, salted with the coarse
  client and platform, is stored: the raw id never leaves the device and the
  cookie. The user agent is reduced to a client ("Chrome", "Safari", the
  Palee app) and a platform ("Windows", "iPhone"), never its version or
  build, so it describes a device without fingerprinting it.

  Pure functions; nothing here reads a database.
  """

  @id_pattern ~r/\A[A-Za-z0-9_-]{16,128}\z/
  @id_bytes 24

  @type description :: %{client: String.t() | nil, platform: String.t() | nil}

  @doc "Whether a device id sent by a client is shaped like one (16-128 url-safe characters)."
  def valid_id?(id) when is_binary(id), do: Regex.match?(@id_pattern, id)
  def valid_id?(_id), do: false

  @doc "A new random device id, for a client that sent none."
  def generate_id,
    do: @id_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc """
  The stored key of a device: SHA-256 of its id and coarse description, so a
  copied id replayed from another kind of browser is a new device.
  """
  def hash(id, %{} = description) when is_binary(id) do
    :crypto.hash(
      :sha256,
      Enum.join(
        ["palee-device", id, description[:client] || "", description[:platform] || ""],
        "|"
      )
    )
  end

  @doc "The coarse client and platform of a user agent (nil when unknown)."
  @spec describe(String.t() | nil) :: description()
  def describe(user_agent) when is_binary(user_agent) do
    ua = String.slice(user_agent, 0, 512)
    %{client: client(ua), platform: platform(ua)}
  end

  def describe(_user_agent), do: %{client: nil, platform: nil}

  @doc """
  A network address shortened to its network part, for an email
  ("203.0.113.x", "2001:db8:85a3::x"): enough to recognise one's home or
  office, without naming the exact machine.
  """
  def coarse_ip({a, b, c, _d}), do: "#{a}.#{b}.#{c}.x"

  def coarse_ip({a, b, c, _d, _e, _f, _g, _h}),
    do: Enum.map_join([a, b, c], ":", &Integer.to_string(&1, 16)) <> "::x"

  def coarse_ip(_ip), do: nil

  # The Palee app's web view appends "PaleeApp" (ADR-171).
  defp client(ua) do
    cond do
      String.contains?(ua, "PaleeApp") -> "app"
      String.contains?(ua, "Edg/") or String.contains?(ua, "EdgA/") -> "Edge"
      String.contains?(ua, "OPR/") -> "Opera"
      String.contains?(ua, "SamsungBrowser/") -> "Samsung Internet"
      String.contains?(ua, "Firefox/") or String.contains?(ua, "FxiOS/") -> "Firefox"
      String.contains?(ua, "Chrome/") or String.contains?(ua, "CriOS/") -> "Chrome"
      String.contains?(ua, "Safari/") -> "Safari"
      true -> nil
    end
  end

  defp platform(ua) do
    cond do
      String.contains?(ua, "iPhone") -> "iPhone"
      String.contains?(ua, "iPad") -> "iPad"
      String.contains?(ua, "Android") -> "Android"
      String.contains?(ua, "CrOS") -> "ChromeOS"
      String.contains?(ua, "Windows") -> "Windows"
      String.contains?(ua, "Macintosh") or String.contains?(ua, "Mac OS X") -> "macOS"
      String.contains?(ua, "Linux") -> "Linux"
      true -> nil
    end
  end
end
