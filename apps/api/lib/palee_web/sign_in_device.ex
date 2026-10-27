defmodule PaleeWeb.SignInDevice do
  @moduledoc """
  ADR-208: which device a sign-in comes from. The device id is the
  `palee_device` cookie (httpOnly, about 400 days, set here), else the
  `x-palee-device-id` header the web app keeps in its storage (the native
  app is the same web app), else a fresh id. Whatever is chosen is set as
  the cookie, so the two converge. Only its hash is ever stored.
  """

  import Plug.Conn

  alias Palee.Identity

  @cookie "palee_device"
  @header "x-palee-device-id"
  @max_age 400 * 24 * 60 * 60

  def cookie_name, do: @cookie
  def header_name, do: @header

  @doc "`{conn, context}`: the conn with the device cookie set, and the sign-in context."
  def context(conn) do
    conn = fetch_cookies(conn)

    device_id =
      [conn.req_cookies[@cookie], conn |> get_req_header(@header) |> List.first()]
      |> Enum.find(&Identity.valid_device_id?/1) || Identity.generate_device_id()

    context = %{
      device_id: device_id,
      user_agent: conn |> get_req_header("user-agent") |> List.first(),
      ip: conn.remote_ip
    }

    {put_resp_cookie(conn, @cookie, device_id, cookie_options()), context}
  end

  defp cookie_options do
    [
      http_only: true,
      secure: Application.get_env(:palee, :env) == :prod,
      same_site: "Lax",
      path: "/api/auth",
      max_age: @max_age
    ]
  end
end
