defmodule Palee.Application.UpdateProfile do
  alias Palee.Application.PasswordVerifier
  alias Palee.Identity
  alias Palee.Workers.PropagateNicknameJob

  def call(user, params) do
    with :ok <- maybe_verify_current_password(user, params) do
      old_nickname = user.nickname

      profile_params =
        params |> Map.drop([:current_password, "current_password"]) |> display_name_alias()

      case Identity.update_profile(user.id, profile_params) do
        {:ok, updated_user} ->
          if updated_user.nickname != old_nickname do
            %{"old_nickname" => old_nickname, "new_nickname" => updated_user.nickname}
            |> PropagateNicknameJob.new()
            |> Oban.insert()
          end

          # ADR-208: a new password is told by email (never the password).
          if new_password?(params),
            do: Palee.Application.SecurityNotices.notify(:password_changed, updated_user)

          {:ok, updated_user}

        {:error, _} = error ->
          error
      end
    end
  end

  # ADR-187: the email and password belong to the login every profile of it
  # shares (and the email is where a reset link goes), so changing either
  # needs the current password.
  # `nickname` is the historical name of the display name (ADR-187).
  defp display_name_alias(params) do
    nickname = Map.get(params, :nickname) || Map.get(params, "nickname")
    display = Map.get(params, :display_name) || Map.get(params, "display_name")
    params = Map.drop(params, [:nickname, "nickname"])

    if is_binary(nickname) and is_nil(display),
      do: Map.put(params, :display_name, nickname),
      else: params
  end

  defp new_password?(params) do
    password = Map.get(params, :password) || Map.get(params, "password")
    is_binary(password) and password != ""
  end

  defp maybe_verify_current_password(user, params) do
    new_password = Map.get(params, :password) || Map.get(params, "password")
    new_email = Map.get(params, :email) || Map.get(params, "email")
    current_password = Map.get(params, :current_password) || Map.get(params, "current_password")

    email_changed? =
      is_binary(new_email) and
        Palee.Organizations.Domain.InvitationEmail.normalize(new_email) != user.email

    if new_password || email_changed? do
      if PasswordVerifier.verify(current_password || "", user.password_hash) do
        :ok
      else
        {:error, :invalid_current_password}
      end
    else
      :ok
    end
  end
end
