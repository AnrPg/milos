defmodule MilosTraining.Infrastructure.Identity.EctoUserStore do
  @behaviour MilosTraining.Identity.Ports.UserStore

  alias MilosTraining.{Identity.Account, Identity.PasswordHasher, Identity.User, Repo}

  @impl true
  def create_user(params) do
    %User{}
    |> User.registration_changeset(params)
    |> maybe_put_password_hash()
    |> Repo.insert()
    |> wrap_result()
  end

  @impl true
  def delete_user(user) do
    case Repo.get(User, user.id) do
      nil ->
        :ok

      %User{} = schema ->
        case Repo.delete(schema) do
          {:ok, _deleted_user} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl true
  def update_user_role(%Account{} = user, role), do: update_user_role(user.id, role)

  def update_user_role(user_id, role) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        user
        |> User.role_changeset(%{role: role})
        |> Repo.update()
        |> wrap_result()
    end
  end

  @impl true
  def get_by_nickname(nil), do: nil

  def get_by_nickname(nickname) do
    Repo.get_by(User, nickname: nickname)
    |> to_account()
  end

  @impl true
  def get_by_id(nil), do: nil

  def get_by_id(id) do
    Repo.get(User, id)
    |> to_account()
  end

  defp maybe_put_password_hash(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp maybe_put_password_hash(changeset) do
    case Ecto.Changeset.get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        Ecto.Changeset.put_change(changeset, :password_hash, PasswordHasher.hash(password))
    end
  end

  defp wrap_result({:ok, %User{} = user}), do: {:ok, to_account(user)}
  defp wrap_result({:error, %Ecto.Changeset{} = changeset}), do: {:error, changeset}

  defp to_account(nil), do: nil

  defp to_account(%User{} = user) do
    %Account{
      id: user.id,
      nickname: user.nickname,
      role: user.role,
      password_hash: user.password_hash,
      leaderboard_opt_in: user.leaderboard_opt_in
    }
  end
end
