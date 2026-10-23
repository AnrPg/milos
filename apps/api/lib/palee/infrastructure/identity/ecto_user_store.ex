defmodule Palee.Infrastructure.Identity.EctoUserStore do
  @behaviour Palee.Identity.Ports.UserStore

  import Ecto.Query

  require Logger

  alias Palee.{
    Identity.Account,
    Identity.Domain.Handle,
    Identity.Domain.NameSearch,
    Identity.Domain.ProductTours,
    Identity.Domain.ProfilePolicy,
    Identity.Login,
    Identity.PasswordHasher,
    Identity.User,
    Repo
  }

  alias Palee.Organizations.Domain.InvitationEmail

  # ADR-187: a new email creates a login and its first profile together.
  @impl true
  def create_login_with_profile(params) do
    Repo.transaction(fn ->
      login_changeset = params |> Login.create_changeset() |> maybe_put_password_hash()
      profile_changeset = User.profile_create_changeset(%User{}, nil, params)

      with {:ok, _profile} <- Ecto.Changeset.apply_action(profile_changeset, :insert),
           :ok <- ensure_handle_free(Ecto.Changeset.get_field(profile_changeset, :handle), nil),
           {:ok, login} <- Repo.insert(login_changeset),
           {:ok, user} <-
             %User{} |> User.profile_create_changeset(login.id, params) |> Repo.insert(),
           {:ok, _login} <- login |> Login.last_used_changeset(user.id) |> Repo.update() do
        load_account(user.id)
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(merge_errors(changeset))
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, account} -> {:ok, account}
      {:error, %Ecto.Changeset{} = changeset} -> email_taken_or(changeset)
      {:error, reason} -> {:error, reason}
    end
  end

  # ADR-187: another profile under an existing login, capped at three. The
  # login row is locked so two concurrent adds cannot both pass the count.
  @impl true
  def add_profile(login_id, params) do
    Repo.transaction(fn ->
      login = Login |> where([l], l.id == ^login_id) |> lock("FOR UPDATE") |> Repo.one()
      count = if login, do: count_profiles(login.id), else: 0

      cond do
        is_nil(login) ->
          Repo.rollback(:not_found)

        not ProfilePolicy.can_add_profile?(count) ->
          Repo.rollback(:profile_limit)

        true ->
          changeset = User.profile_create_changeset(%User{}, login.id, params)

          with :ok <- ensure_handle_free(Ecto.Changeset.get_field(changeset, :handle), nil),
               {:ok, user} <- Repo.insert(changeset) do
            load_account(user.id)
          else
            {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  @impl true
  def get_login_by_email(email) when is_binary(email) do
    normalized = InvitationEmail.normalize(email)

    Login
    |> where([l], fragment("lower(?)", l.email) == ^normalized)
    |> Repo.one()
    |> case do
      nil ->
        nil

      login ->
        %{
          id: login.id,
          email: login.email,
          password_hash: login.password_hash,
          last_used_user_id: login.last_used_user_id,
          profile_count: count_profiles(login.id)
        }
    end
  end

  def get_login_by_email(_email), do: nil

  @doc "The profile an email signs in to: the last one used, else the oldest."
  @impl true
  def get_by_email(email) do
    case get_login_by_email(email) do
      nil ->
        nil

      %{id: login_id, last_used_user_id: last_used} ->
        (last_used && get_by_id(last_used)) || login_id |> list_profiles() |> List.first()
    end
  end

  @impl true
  def list_profiles(login_id) do
    profiles_query()
    |> where([user], user.login_id == ^login_id)
    |> order_by([user], asc: user.inserted_at, asc: user.id)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def touch_last_used(login_id, user_id) do
    Login
    |> where([l], l.id == ^login_id)
    |> Repo.update_all(
      set: [last_used_user_id: user_id, updated_at: NaiveDateTime.utc_now(:second)]
    )

    :ok
  end

  @impl true
  def handle_available?(handle, except_user_id \\ nil) do
    normalized = Handle.normalize(handle)

    Handle.well_formed?(normalized) and ensure_handle_free(normalized, except_user_id) == :ok
  end

  @doc "ADR-187: a new email and/or password for the login behind `user_id`."
  @impl true
  def update_credentials(user_id, params) do
    Repo.transaction(fn ->
      with %User{} = user <- Repo.get(User, user_id) || {:error, :not_found},
           login when not is_nil(login) <-
             Login |> where([l], l.id == ^user.login_id) |> lock("FOR UPDATE") |> Repo.one(),
           changeset =
             login
             |> Login.credentials_changeset(params)
             |> maybe_put_password_hash()
             |> maybe_bump_login_security(),
           {:ok, _login} <- Repo.update(changeset) do
        load_account(user.id)
      else
        nil -> Repo.rollback(:not_found)
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "ADR-187: sets a new password on a login and revokes every profile's sessions."
  @impl true
  def reset_login_password(login_id, password) do
    case Repo.get(Login, login_id) do
      nil ->
        {:error, :not_found}

      login ->
        login
        |> Login.credentials_changeset(%{password: password})
        |> maybe_put_password_hash()
        |> maybe_bump_login_security()
        |> Repo.update()
        |> case do
          {:ok, _login} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def delete_user(user) do
    Repo.transaction(fn ->
      admins =
        User
        |> where([user], user.role == :admin)
        |> order_by([user], asc: user.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      case User |> where([user], user.id == ^user.id) |> lock("FOR UPDATE") |> Repo.one() do
        nil ->
          :ok

        %User{role: :admin} when length(admins) <= 1 ->
          Repo.rollback(:last_admin)

        %User{} = schema ->
          case Repo.delete(schema) do
            {:ok, _deleted_user} -> delete_login_without_profiles(schema.login_id)
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
    |> case do
      {:ok, :ok} ->
        :ok

      {:error, :last_admin} ->
        {:error, :last_admin}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in Ecto.ConstraintError -> restricted_history(error)
  end

  @impl true
  def delete_tenant_scoped_user(user) do
    case User |> where([schema], schema.id == ^user.id) |> Repo.one() do
      nil ->
        :ok

      %User{} = schema ->
        Repo.transaction(fn ->
          case Repo.delete(schema) do
            {:ok, _deleted_user} -> delete_login_without_profiles(schema.login_id)
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, :ok} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  rescue
    error in Ecto.ConstraintError ->
      {:error, :user_has_restricted_history} = restricted_history(error)
      {:error, {:user_has_restricted_history, blocking_record(error.constraint)}}
  end

  # Another record still needs the account (a RESTRICT reference). Name the
  # constraint in the log so the blocker is findable without a database shell.
  defp restricted_history(%Ecto.ConstraintError{constraint: constraint}) do
    Logger.warning("account delete blocked by constraint #{constraint}")
    {:error, :user_has_restricted_history}
  end

  # "finance_entitlement_usage_entries_membership_id_fkey" ->
  # "finance_entitlement_usage_entries_membership_id": the table and column
  # that still hold the account, without any personal data.
  defp blocking_record(constraint) when is_binary(constraint),
    do: String.replace_suffix(constraint, "_fkey", "")

  defp blocking_record(_constraint), do: "unknown"

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

      changeset =
        user
        |> User.role_changeset(%{role: role})
        |> maybe_revoke_sessions_after_role_change()

      next_role = Ecto.Changeset.get_field(changeset, :role)

      if user.role == :admin and next_role != :admin and length(admins) <= 1 do
        Repo.rollback(:last_admin)
      end

      case Repo.update(changeset) do
        {:ok, updated} -> load_account(updated.id)
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
        {:ok, updated} -> load_account(updated.id)
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
    profiles_query()
    |> where([user], user.handle == ^Handle.normalize(nickname))
    |> Repo.one()
    |> to_account()
  end

  @impl true
  def get_by_id(nil), do: nil

  def get_by_id(id) do
    profiles_query()
    |> where([user], user.id == ^id)
    |> Repo.one()
    |> to_account()
  end

  @impl true
  def list_by_ids(ids) when is_list(ids) do
    ids = Enum.uniq(ids)

    profiles_query()
    |> where([user], user.id in ^ids)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def list_by_role(role) when is_binary(role), do: list_by_role(String.to_existing_atom(role))

  def list_by_role(role) when is_atom(role) do
    profiles_query()
    |> where([user], user.role == ^role)
    |> order_by([user], asc: user.handle)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def list_all_users do
    profiles_query()
    |> order_by([user], asc: user.handle)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def search_athletes(nil), do: list_by_role(:athlete)
  def search_athletes(""), do: list_by_role(:athlete)

  def search_athletes(query) do
    profiles_query()
    |> where([user], user.role == :athlete)
    |> matching_name(query)
    |> order_by([user], asc: user.handle)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  @impl true
  def update_profile(user_id, params) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        update_profile_and_credentials(user, params)
    end
  end

  # Profile fields change on the profile; email and password on its login.
  # One transaction so a bad password never leaves a half-applied edit.
  defp update_profile_and_credentials(user, params) do
    credential_params = Map.take(stringify(params), ["email", "password"])
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      changeset = User.profile_changeset(user, params, now)
      new_handle = Ecto.Changeset.get_change(changeset, :handle)

      with :ok <- handle_change_allowed(user, new_handle, now),
           :ok <- ensure_handle_free(new_handle, user.id),
           {:ok, updated} <- Repo.update(changeset),
           :ok <- reserve_old_handle(user, new_handle, now),
           :ok <- maybe_update_credentials(user, credential_params) do
        load_account(updated.id)
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp maybe_update_credentials(_user, params) when map_size(params) == 0, do: :ok

  defp maybe_update_credentials(user, params) do
    Login
    |> where([l], l.id == ^user.login_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> Login.credentials_changeset(params)
    |> maybe_put_password_hash()
    |> maybe_bump_login_security()
    |> Repo.update()
    |> case do
      {:ok, _login} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp handle_change_allowed(_user, nil, _now), do: :ok

  defp handle_change_allowed(user, _new_handle, now) do
    case ProfilePolicy.next_handle_change(user.handle_changed_at, now) do
      :now ->
        :ok

      %DateTime{} = allowed_at ->
        {:error,
         user
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.add_error(:handle, "can be changed again on %{date}",
           date: Date.to_iso8601(DateTime.to_date(allowed_at))
         )}
    end
  end

  defp reserve_old_handle(_user, nil, _now), do: :ok

  defp reserve_old_handle(user, _new_handle, now) do
    Repo.insert_all(
      "handle_reservations",
      [
        %{
          handle: user.handle,
          user_id: Ecto.UUID.dump!(user.id),
          reserved_until: ProfilePolicy.reservation_ends_at(now),
          inserted_at: NaiveDateTime.utc_now(:second)
        }
      ],
      on_conflict: {:replace, [:user_id, :reserved_until]},
      conflict_target: [:handle]
    )

    :ok
  end

  # A handle held by another profile, or reserved for another profile after a
  # rename, is not free. The unique index stays the final word on races.
  defp ensure_handle_free(nil, _except_user_id), do: :ok

  defp ensure_handle_free(handle, except_user_id) do
    except = except_user_id && Ecto.UUID.dump!(except_user_id)

    taken? =
      User
      |> where([user], user.handle == ^handle)
      |> maybe_except(except_user_id)
      |> Repo.exists?()

    reserved? =
      "handle_reservations"
      |> where([r], r.handle == ^handle and r.reserved_until > ^DateTime.utc_now())
      |> then(fn query ->
        if except, do: where(query, [r], r.user_id != ^except), else: query
      end)
      |> Repo.exists?()

    if taken? or reserved? do
      {:error,
       %User{}
       |> Ecto.Changeset.change()
       |> Ecto.Changeset.add_error(:handle, "has already been taken")}
    else
      :ok
    end
  end

  defp maybe_except(query, nil), do: query
  defp maybe_except(query, user_id), do: where(query, [user], user.id != ^user_id)

  @impl true
  def mark_tour_completed(user_id, audience) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        with {:ok, completed} <- ProductTours.complete(user.completed_tours, audience) do
          user
          |> User.tours_changeset(completed)
          |> Repo.update()
          |> wrap_result()
        end
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
  def update_time_zone(user_id, time_zone) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{time_zone: ^time_zone} = user ->
        {:ok, load_account(user.id)}

      %User{} = user ->
        user
        |> User.time_zone_changeset(time_zone)
        |> Repo.update()
        |> wrap_result()
    end
  end

  @impl true
  def search_users(nil), do: search_users("")

  def search_users("") do
    profiles_query()
    |> order_by([u], asc: u.handle)
    |> limit(20)
    |> Repo.all()
    |> Enum.map(&to_account/1)
  end

  def search_users(query) do
    profiles_query()
    |> matching_name(query)
    |> order_by(
      [u],
      fragment("CASE WHEN ? = ? THEN 0 ELSE 1 END", u.handle, ^Handle.normalize(query))
    )
    |> order_by([u], asc: u.handle)
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

  defp ilike_pattern(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%#{escaped}%"
  end

  defp wrap_result({:ok, %User{} = user}), do: {:ok, load_account(user.id)}
  defp wrap_result({:error, %Ecto.Changeset{} = changeset}), do: {:error, changeset}

  defp profiles_query do
    from(user in User, join: login in assoc(user, :login), preload: [login: login])
  end

  defp load_account(user_id), do: get_by_id(user_id)

  defp count_profiles(login_id) do
    User
    |> where([user], user.login_id == ^login_id)
    |> select([user], count(user.id))
    |> Repo.one()
  end

  # ADR-187: a query finds a profile by its @handle or by the folded search
  # key of its display name (own script and Latin form).
  defp matching_name(query, text) do
    handle_pattern = ilike_pattern(Handle.normalize(text) || "")
    name_pattern = ilike_pattern(NameSearch.fold(text))

    if handle_pattern == "%%" do
      where(query, [u], fragment("? ILIKE ? ESCAPE '\\'", u.search_text, ^name_pattern))
    else
      where(
        query,
        [u],
        fragment("? ILIKE ? ESCAPE '\\'", u.handle, ^handle_pattern) or
          fragment("? ILIKE ? ESCAPE '\\'", u.search_text, ^name_pattern)
      )
    end
  end

  defp delete_login_without_profiles(login_id) do
    if count_profiles(login_id) == 0 do
      Login |> where([l], l.id == ^login_id) |> Repo.delete_all()
    end

    :ok
  end

  defp maybe_bump_login_security(changeset) do
    if Ecto.Changeset.changed?(changeset, :password_hash),
      do:
        Ecto.Changeset.put_change(
          changeset,
          :security_version,
          (changeset.data.security_version || 0) + 1
        ),
      else: changeset
  end

  defp email_taken_or(changeset) do
    if Keyword.has_key?(changeset.errors, :email) and
         Enum.any?(changeset.errors, fn
           {:email, {_msg, opts}} -> opts[:constraint] == :unique
           _ -> false
         end),
       do: {:error, :email_taken},
       else: {:error, changeset}
  end

  # Login and profile errors surface as one changeset keyed by field.
  defp merge_errors(%Ecto.Changeset{} = changeset), do: changeset

  defp stringify(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

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

  @impl true
  def bump_security_version(user_id) do
    Repo.transaction(fn ->
      case User |> where([user], user.id == ^user_id) |> lock("FOR UPDATE") |> Repo.one() do
        nil ->
          Repo.rollback(:not_found)

        user ->
          user
          |> User.security_version_changeset((user.security_version || 1) + 1)
          |> Repo.update()
          |> case do
            {:ok, updated} -> load_account(updated.id)
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> case do
      {:ok, account} -> {:ok, account}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_account(nil), do: nil

  defp to_account(%User{login: %Login{} = login} = user) do
    %Account{
      id: user.id,
      nickname: user.display_name || user.handle,
      handle: user.handle,
      normalized_nickname: user.handle,
      search_text: user.search_text,
      login_id: user.login_id,
      handle_changed_at: user.handle_changed_at,
      role: user.role,
      password_hash: login.password_hash,
      calendar_feed_token_version: user.calendar_feed_token_version || 1,
      # Profile and login versions both only grow, so their sum changes
      # whenever either is bumped (ADR-187): a password reset on the login
      # revokes every profile's tokens without a second claim.
      security_version: (user.security_version || 1) + (login.security_version || 0),
      avatar_url: user.avatar_url,
      preferred_locale: user.preferred_locale || "en",
      preferred_theme_slug: user.preferred_theme_slug,
      time_zone: user.time_zone,
      email: login.email,
      inserted_at: user.inserted_at,
      completed_tours: user.completed_tours || []
    }
  end

  defp maybe_revoke_sessions_after_role_change(changeset) do
    if Ecto.Changeset.changed?(changeset, :role) do
      Ecto.Changeset.put_change(
        changeset,
        :security_version,
        (changeset.data.security_version || 1) + 1
      )
    else
      changeset
    end
  end
end
