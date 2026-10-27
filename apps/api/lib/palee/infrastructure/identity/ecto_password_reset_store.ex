defmodule Palee.Infrastructure.Identity.EctoPasswordResetStore do
  @moduledoc "Postgres storage of password reset requests, their log and recovery codes (ADR-187)."
  @behaviour Palee.Identity.Ports.PasswordResetStore

  import Ecto.Query

  alias Palee.Identity.{
    PasswordResetLogEntry,
    PasswordResetRequest,
    RecoveryCode,
    User
  }

  alias Palee.Repo

  @impl true
  def handlers(login_id) do
    %{rows: rows} =
      Repo.query!(
        "SELECT user_id, source, organization_id, organization_name FROM palee_password_reset_handlers($1)",
        [Ecto.UUID.dump!(login_id)]
      )

    Enum.map(rows, fn [user_id, source, organization_id, organization_name] ->
      %{
        user_id: Ecto.UUID.load!(user_id),
        source: source,
        organization_id: organization_id && Ecto.UUID.load!(organization_id),
        organization_name: organization_name
      }
    end)
  end

  @impl true
  def get_request(id), do: Repo.get(PasswordResetRequest, id)

  @impl true
  def get_request_for_login(login_id),
    do: Repo.get_by(PasswordResetRequest, login_id: login_id)

  @impl true
  def get_request_by_token_hash(hash),
    do: Repo.get_by(PasswordResetRequest, link_token_hash: hash)

  @impl true
  def lock_request_by_token_hash(hash) do
    PasswordResetRequest
    |> where([request], request.link_token_hash == ^hash)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  @impl true
  def count_requests_from(requester_key, since) do
    PasswordResetRequest
    |> where([request], request.requester_key == ^requester_key)
    |> where([request], request.inserted_at >= ^since)
    |> Repo.aggregate(:count)
  end

  @impl true
  def transaction(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def create_request(params) do
    params
    |> PasswordResetRequest.create_changeset()
    |> Repo.insert()
  end

  @impl true
  def update_request_locked(id, fun) do
    Repo.transaction(fn ->
      request =
        PasswordResetRequest
        |> where([request], request.id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %PasswordResetRequest{} <- request || {:error, :not_found},
           {:ok, changes} <- fun.(request),
           {:ok, updated} <-
             request |> PasswordResetRequest.update_changeset(changes) |> Repo.update() do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def delete_request(id) do
    PasswordResetRequest |> where([request], request.id == ^id) |> Repo.delete_all()
    :ok
  end

  @impl true
  def inbox(viewer_id) do
    hidden =
      from(hide in "password_reset_request_hides",
        where: hide.viewer_user_id == type(^viewer_id, :binary_id),
        select: hide.request_id
      )

    PasswordResetRequest
    |> where([request], request.id not in subquery(hidden))
    |> order_by([request], desc: request.inserted_at)
    |> preload([:user, :claimed_by, login: []])
    |> Repo.all()
    |> Enum.flat_map(fn request ->
      case entry(request, viewer_id) do
        nil -> []
        entry -> [entry]
      end
    end)
  end

  @impl true
  def inbox_entry(viewer_id, request_id) do
    case PasswordResetRequest
         |> preload([:user, :claimed_by, login: []])
         |> Repo.get(request_id) do
      nil -> nil
      request -> entry(request, viewer_id)
    end
  end

  defp entry(request, viewer_id) do
    case Enum.filter(handlers(request.login_id), &(&1.user_id == viewer_id)) do
      [] ->
        nil

      roles ->
        %{
          request: request,
          person: person(request.user, request.login),
          claimer: request.claimed_by && person(request.claimed_by, nil),
          sources: roles |> Enum.map(& &1.source) |> Enum.uniq(),
          organizations:
            roles |> Enum.map(& &1.organization_name) |> Enum.reject(&is_nil/1) |> Enum.uniq()
        }
    end
  end

  defp person(%User{} = user, login) do
    %{
      user_id: user.id,
      login_id: user.login_id,
      handle: user.handle,
      display_name: user.display_name,
      avatar_url: user.avatar_url,
      email: login && login.email
    }
  end

  @impl true
  def hide(request_id, viewer_id) do
    Repo.insert_all(
      "password_reset_request_hides",
      [
        %{
          request_id: Ecto.UUID.dump!(request_id),
          viewer_user_id: Ecto.UUID.dump!(viewer_id),
          inserted_at: DateTime.utc_now()
        }
      ],
      on_conflict: :nothing
    )

    :ok
  end

  @impl true
  def log(params) do
    Repo.insert_all(PasswordResetLogEntry, [
      params
      |> Map.take([:login_id, :user_id, :handle, :handler_user_id, :handler_handle, :event])
      |> Map.put(:id, Ecto.UUID.generate())
      |> Map.put(:inserted_at, DateTime.utc_now())
    ])

    :ok
  end

  @impl true
  def list_log(limit) do
    PasswordResetLogEntry
    |> order_by([entry], desc: entry.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(
      &Map.take(&1, [
        :id,
        :user_id,
        :handle,
        :handler_user_id,
        :handler_handle,
        :event,
        :inserted_at
      ])
    )
  end

  @impl true
  def replace_recovery_codes(login_id, hashes) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      RecoveryCode |> where([code], code.login_id == ^login_id) |> Repo.delete_all()

      Repo.insert_all(
        RecoveryCode,
        Enum.map(hashes, fn hash ->
          %{id: Ecto.UUID.generate(), login_id: login_id, code_hash: hash, inserted_at: now}
        end)
      )
    end)

    :ok
  end

  @impl true
  def count_recovery_codes(login_id) do
    RecoveryCode
    |> where([code], code.login_id == ^login_id)
    |> select([code], %{
      total: count(code.id),
      unused: filter(count(code.id), is_nil(code.used_at))
    })
    |> Repo.one()
  end

  @impl true
  def use_recovery_code(login_id, hash, now) do
    {count, _rows} =
      RecoveryCode
      |> where(
        [code],
        code.login_id == ^login_id and code.code_hash == ^hash and is_nil(code.used_at)
      )
      |> Repo.update_all(set: [used_at: now])

    if count > 0, do: :ok, else: {:error, :invalid}
  end
end
