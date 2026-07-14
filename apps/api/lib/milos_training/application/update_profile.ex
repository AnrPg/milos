defmodule MilosTraining.Application.UpdateProfile do
  alias MilosTraining.Application.PasswordVerifier
  alias MilosTraining.Identity
  alias MilosTraining.Workers.PropagateNicknameJob

  def call(user, params) do
    with :ok <- maybe_verify_current_password(user, params) do
      old_nickname = user.nickname
      profile_params = Map.drop(params, [:current_password, "current_password"])

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
