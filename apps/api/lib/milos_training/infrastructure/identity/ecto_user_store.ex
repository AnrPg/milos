defmodule MilosTraining.Infrastructure.Identity.EctoUserStore do
  @behaviour MilosTraining.Identity.Ports.UserStore

  import Ecto.Query

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
    Repo.transaction(fn ->
      admins =
        User
        |> where([user], user.role == :admin)
        |> order_by([user], asc: user.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      user =
        User
        |> where([user], user.id == ^user_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(user) do
        Repo.rollback(:not_found)
      end

      changeset = User.role_changeset(user, %{role: role})
      next_role = Ecto.Changeset.get_field(changeset, :role)

      if user.role == :admin and next_role != :admin and length(admins) <= 1 do
        Repo.rollback(:last_admin)
      end

      case Repo.update(changeset) do
        {:ok, updated} -> to_account(updated)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, %Account{} = account} -> {:ok, account}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :last_admin} -> {:error, :last_admin}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @impl true
  def regenerate_calendar_feed_token(%Account{} = user),
    do: regenerate_calendar_feed_token(user.id)

  def regenerate_calendar_feed_token(user_id) do
    Repo.transaction(fn ->
      user =
        User
        |> where([user], user.id == ^user_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(user) do
        Repo.rollback(:not_found)
      end

      next_version = (user.calendar_feed_token_version || 1) + 1

      user
      |> User.calendar_feed_token_changeset(%{calendar_feed_token_version: next_version})
      |> Repo.update()
      |> case do
        {:ok, updated} -> to_account(updated)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, %Account{} = account} -> {:ok, account}
      {:error, :not_found} -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
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

  @impl true
  def list_by_ids(ids) when is_list(ids) do
    ids = Enum.uniq(ids)

    User
    |> where([user], user.id in ^ids)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def list_by_role(role) when is_binary(role), do: list_by_role(String.to_existing_atom(role))

  def list_by_role(role) when is_atom(role) do
    User
    |> where([user], user.role == ^role)
    |> order_by([user], asc: user.nickname)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def list_all_users do
    User
    |> order_by([user], asc: user.nickname)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def search_athletes(nil), do: list_by_role(:athlete)
  def search_athletes(""), do: list_by_role(:athlete)

  def search_athletes(query) do
    pattern = "%#{query}%"

    User
    |> where([user], user.role == :athlete)
    |> where([user], ilike(user.nickname, ^pattern))
    |> order_by([user], asc: user.nickname)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def update_profile(user_id, params) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        user
        |> User.profile_changeset(params)
        |> maybe_put_password_hash()
        |> Repo.update()
        |> wrap_result()
    end
  end

  @impl true
  def update_avatar(user_id, avatar_url) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        user
        |> User.avatar_changeset(%{avatar_url: avatar_url})
        |> Repo.update()
        |> wrap_result()
    end
  end

  @impl true
  def search_users(nil), do: search_users("")

  def search_users("") do
    User
    |> order_by([u], asc: u.nickname)
    |> limit(20)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  def search_users(query) do
    pattern = "%#{query}%"

    User
    |> where([u], ilike(u.nickname, ^pattern))
    |> order_by([u], asc: u.nickname)
    |> limit(20)
    |> Repo.all()
    |> Enum.map(&to_account/1)
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

  @impl true
  def count_by_role(role) when is_binary(role),
    do: count_by_role(String.to_existing_atom(role))

  @impl true
  def count_by_role(role) when is_atom(role) do
    User
    |> where([u], u.role == ^role)
    |> select([u], count(u.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp to_account(nil), do: nil

  defp to_account(%User{} = user) do
    %Account{
      id: user.id,
      nickname: user.nickname,
      role: user.role,
      password_hash: user.password_hash,
      calendar_feed_token_version: user.calendar_feed_token_version || 1,
      avatar_url: user.avatar_url,
      inserted_at: user.inserted_at
    }
  end
end
