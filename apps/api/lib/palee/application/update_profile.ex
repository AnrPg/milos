defmodule Palee.Application.UpdateProfile do
  alias Palee.Application.PasswordVerifier
  alias Palee.Identity
  alias Palee.Workers.PropagateNicknameJob

  def call(user, params) do
    with :ok <- refuse_direct_email_change(user, params),
         :ok <- maybe_verify_current_password(user, params) do
      old_nickname = user.nickname

      profile_params =
        params
        |> Map.drop([:current_password, "current_password", :email, "email"])
        |> display_name_alias()

      case Identity.update_profile(user.id, profile_params) do
        {:ok, updated_user} ->
          if updated_user.nickname != old_nickname do
            %{"old_nickname" => old_nickname, "new_nickname" => updated_user.nickname}
            |> PropagateNicknameJob.new()
            |> Oban.insert()
          end

          {:ok, updated_user}

        {:error, _} = error ->
          error
      end
    end
  end

  # ADR-207: a new email takes effect only once its inbox confirms it
  # (`Palee.Application.EmailChange`), never through a profile edit. The
  # unchanged address may still come along with the form.
  defp refuse_direct_email_change(user, params) do
    new_email = Map.get(params, :email) || Map.get(params, "email")

    if is_binary(new_email) and new_email != "" and
         Palee.Organizations.Domain.InvitationEmail.normalize(new_email) !=
           Palee.Organizations.Domain.InvitationEmail.normalize(user.email),
       do: {:error, :email_change_needs_confirmation},
       else: :ok
  end

  # ADR-187: the password belongs to the login every profile of it shares,
  # so changing it needs the current password.
  # `nickname` is the historical name of the display name (ADR-187).
  defp display_name_alias(params) do
    nickname = Map.get(params, :nickname) || Map.get(params, "nickname")
    display = Map.get(params, :display_name) || Map.get(params, "display_name")
    params = Map.drop(params, [:nickname, "nickname"])

    if is_binary(nickname) and is_nil(display),
      do: Map.put(params, :display_name, nickname),
      else: params
  end

  defp maybe_verify_current_password(user, params) do
    new_password = Map.get(params, :password) || Map.get(params, "password")
    current_password = Map.get(params, :current_password) || Map.get(params, "current_password")

    if new_password do
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
