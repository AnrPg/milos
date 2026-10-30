defmodule Palee.Application.BoxScreens.DisplayToken do
  @moduledoc """
  The box screen's display token (ADR-253), signed with the `SignedToken`
  port under its own salt. It names the box, the screen and the screen's
  token version, nothing about a person or a role, and lives 90 days (the TV
  renews it long before). It opens only `/api/box-screen/*` and
  `/box_screen_socket`: no other plug or socket accepts this salt.

  A token stops working when its screen is removed, or when another device
  pairs with a new code (the token version moves on).
  """

  alias Palee.Application.SignedToken

  @salt "box-screen-v1"
  @max_age_days 90

  def max_age_seconds, do: @max_age_days * 86_400

  @doc "`%{token, expires_at}` for a paired screen."
  def issue(%{organization_id: organization_id, id: screen_id, token_version: version}, now) do
    token =
      SignedToken.sign(@salt, %{"o" => organization_id, "s" => screen_id, "v" => version})

    %{
      token: token,
      expires_at: now |> DateTime.add(max_age_seconds(), :second) |> DateTime.truncate(:second)
    }
  end

  @doc "`{:ok, %{organization_id, screen_id, token_version}}` or `{:error, :invalid_screen_token}`."
  def verify(token) when is_binary(token) do
    case SignedToken.verify(@salt, token, max_age: max_age_seconds()) do
      {:ok, %{"o" => organization_id, "s" => screen_id, "v" => version}}
      when is_binary(organization_id) and is_binary(screen_id) and is_integer(version) ->
        {:ok, %{organization_id: organization_id, screen_id: screen_id, token_version: version}}

      _invalid ->
        {:error, :invalid_screen_token}
    end
  end

  def verify(_token), do: {:error, :invalid_screen_token}
end
