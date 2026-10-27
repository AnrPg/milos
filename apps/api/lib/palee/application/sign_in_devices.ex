defmodule Palee.Application.SignInDevices do
  @moduledoc """
  ADR-208: the new-sign-in alert. Every password sign-in remembers its
  device (a hash of the device's random id and coarse user agent); a
  sign-in from a device the login has never signed in from sends the
  `:new_sign_in` security notice with the device, the network and a "sign
  out everywhere" link. The first sign-in of a login, and the device it
  signed up on, never alert. A token refresh is not a sign-in.

  `context`: `device_id` (already chosen by the web layer: the client's
  cookie or header, or a fresh one), `user_agent`, `ip`.
  """

  require Logger

  alias Palee.Application.SecurityNotices
  alias Palee.Identity

  @doc "Remembers the device of a password sign-in and alerts when it is new. Always `:ok`."
  def signed_in(account, context, now \\ DateTime.utc_now()),
    do: remember(account, context, :sign_in, now)

  @doc "Remembers the device an account was created on (never alerts). Always `:ok`."
  def signed_up(account, context, now \\ DateTime.utc_now()),
    do: remember(account, context, :sign_up, now)

  defp remember(%{login_id: login_id} = account, %{device_id: device_id} = context, source, now)
       when is_binary(login_id) and is_binary(device_id) do
    user_agent = Map.get(context, :user_agent)

    case Identity.remember_sign_in_device(login_id, device_id, user_agent, source, now) do
      {:new, description} ->
        SecurityNotices.notify(:new_sign_in, account, %{
          at: now,
          device: description,
          ip: Map.get(context, :ip)
        })

      {_known_or_first, _description} ->
        :ok
    end
  rescue
    error ->
      Logger.error("sign_in_device_failed error=#{Exception.message(error)}")
      :ok
  end

  defp remember(_account, _context, _source, _now), do: :ok
end
