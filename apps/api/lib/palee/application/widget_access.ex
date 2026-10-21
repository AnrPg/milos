defmodule Palee.Application.WidgetAccess do
  @moduledoc """
  The widget token (ADR-173). Home-screen widgets run outside the web view,
  without the app's session, so the app hands them a token of their own:

    * `issue/2` (`POST /api/me/widget-tokens`): a row per app install and a
      signed token naming it, the person and their security version. A
      token for the same install replaces the previous one (`replaces_id`);
      a person keeps at most #{10} installs;
    * `revoke/2` (`DELETE /api/me/widget-tokens/:id`, sign-out): the row
      goes, so the token stops working at once;
    * `authenticate/1`: the widget's `Authorization: Bearer` token back to
      the person, valid while its row exists, the security version matches
      (a password change or «αποσύνδεση παντού» revokes it) and it is younger
      than #{180} days (the app renews it long before).

  The token only reaches the widget endpoints: the snapshot and «+1 νερό».
  """

  alias Palee.Application.SignedToken
  alias Palee.{Identity, Widgets}
  alias Palee.Identity.UserContext

  @salt "widget-v1"
  @max_age_days 180
  @max_installs 10

  def issue(%{user_id: user_id, account: account}, params) do
    with {:ok, row} <-
           Widgets.create_token(%{user_id: user_id, platform: param(params, :platform)}) do
      case param(params, :replaces_id) do
        id when is_binary(id) and id != row.id -> Widgets.delete_token(user_id, id)
        _none -> false
      end

      Widgets.prune_tokens(user_id, @max_installs)

      token =
        SignedToken.sign(@salt, %{
          "u" => user_id,
          "i" => row.id,
          "v" => Map.get(account, :security_version)
        })

      {:ok,
       %{
         id: row.id,
         token: token,
         expires_at: DateTime.add(row.inserted_at, @max_age_days * 86_400, :second)
       }}
    end
  end

  def revoke(%{user_id: user_id}, id) do
    if Widgets.delete_token(user_id, id), do: :ok, else: {:error, :not_found}
  end

  @doc "The person's `UserContext` for a widget token, or `{:error, :invalid_widget_token}`."
  def authenticate(token) when is_binary(token) do
    with {:ok, %{"u" => user_id, "i" => id} = claims} <-
           SignedToken.verify(@salt, token, max_age: @max_age_days * 86_400),
         %{} <- Widgets.get_token(user_id, id),
         %{} = account <- Identity.find_by_id(user_id),
         true <- Map.get(account, :security_version) == claims["v"] do
      {:ok, UserContext.new(account, %{transport: :widget})}
    else
      _invalid -> {:error, :invalid_widget_token}
    end
  end

  def authenticate(_token), do: {:error, :invalid_widget_token}

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
