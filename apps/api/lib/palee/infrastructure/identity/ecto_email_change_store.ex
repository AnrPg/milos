defmodule Palee.Infrastructure.Identity.EctoEmailChangeStore do
  @moduledoc "Postgres storage of ADR-207's pending email changes."
  @behaviour Palee.Identity.Ports.EmailChangeStore

  import Ecto.Query

  alias Palee.Identity.{Login, PendingEmailChange}
  alias Palee.Repo

  @impl true
  def transaction(fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def get_login(login_id), do: login_id |> login_query() |> Repo.one()

  @impl true
  def lock_login(login_id), do: login_id |> login_query() |> lock("FOR UPDATE") |> Repo.one()

  defp login_query(login_id) do
    Login
    |> where([l], l.id == ^login_id)
    |> select([l], %{
      id: l.id,
      email: l.email,
      email_change_locked_until: l.email_change_locked_until
    })
  end

  @impl true
  def get_pending(login_id), do: Repo.get_by(PendingEmailChange, login_id: login_id)

  @impl true
  def put_pending(login_id, new_email, requested_at, expires_at) do
    %PendingEmailChange{}
    |> Ecto.Changeset.change(
      login_id: login_id,
      new_email: new_email,
      requested_at: requested_at,
      expires_at: expires_at
    )
    |> Repo.insert(
      on_conflict: {:replace, [:new_email, :requested_at, :expires_at, :updated_at]},
      conflict_target: [:login_id],
      returning: true
    )
  end

  @impl true
  def delete_pending(login_id) do
    {_count, _rows} =
      PendingEmailChange |> where([p], p.login_id == ^login_id) |> Repo.delete_all()

    :ok
  end

  @impl true
  def email_taken?(email, except_login_id) do
    Login
    |> where([l], fragment("lower(?)", l.email) == ^String.downcase(email))
    |> where([l], l.id != ^except_login_id)
    |> Repo.exists?()
  end

  @impl true
  def set_login_email(login_id, email, now, opts) do
    case Repo.get(Login, login_id) do
      nil ->
        {:error, :not_found}

      login ->
        changes =
          [email: email, email_verified_at: now, security_version: login.security_version + 1]
          |> then(fn changes ->
            case Keyword.fetch(opts, :locked_until) do
              {:ok, until} -> Keyword.put(changes, :email_change_locked_until, until)
              :error -> changes
            end
          end)

        login
        |> Ecto.Changeset.change(changes)
        |> Ecto.Changeset.unique_constraint(:email, name: :logins_email_unique_index)
        |> Repo.update()
        |> case do
          {:ok, _login} -> delete_pending(login_id)
          {:error, %Ecto.Changeset{}} -> {:error, :email_unavailable}
        end
    end
  end
end
