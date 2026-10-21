defmodule Palee.Infrastructure.Wallet.EctoWalletStore do
  @moduledoc "Ecto adapter of the Wallet store (ADR-155)."

  @behaviour Palee.Wallet.Ports.WalletStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Wallet.{DeviceRegistration, WalletPass}

  @impl true
  def create_pass(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> WalletPass.create_changeset()
    |> Repo.insert()
    |> normalize_result()
  end

  @impl true
  def get_active_pass(%{organization_id: organization_id}, user_id, platform) do
    WalletPass
    |> where(
      [pass],
      pass.organization_id == ^organization_id and pass.user_id == ^user_id and
        pass.platform == ^platform and is_nil(pass.revoked_at)
    )
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def get_pass_by_serial(%{organization_id: organization_id}, serial) do
    WalletPass
    |> where([pass], pass.organization_id == ^organization_id and pass.serial == ^serial)
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def get_pass(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        WalletPass |> Repo.get_by(id: id, organization_id: organization_id) |> normalize()

      :error ->
        nil
    end
  end

  @impl true
  def revoke_pass(%{organization_id: organization_id}, id, at) do
    case Repo.get_by(WalletPass, id: id, organization_id: organization_id) do
      nil ->
        {:error, :not_found}

      %WalletPass{revoked_at: nil} = pass ->
        pass
        |> Ecto.Changeset.change(revoked_at: at, last_updated_at: at)
        |> Repo.update()
        |> normalize_result()

      pass ->
        {:ok, normalize(pass)}
    end
  end

  @impl true
  def revoke_code_passes(%{organization_id: organization_id}, code_ids, at) do
    {_count, passes} =
      WalletPass
      |> where(
        [pass],
        pass.organization_id == ^organization_id and pass.member_code_id in ^code_ids and
          is_nil(pass.revoked_at)
      )
      |> select([pass], pass)
      |> Repo.update_all(set: [revoked_at: at, last_updated_at: at, updated_at: at])

    Enum.map(passes, &normalize/1)
  end

  @impl true
  def touch_user_passes(%{organization_id: organization_id}, user_id, at) do
    {_count, passes} =
      WalletPass
      |> where(
        [pass],
        pass.organization_id == ^organization_id and pass.user_id == ^user_id and
          is_nil(pass.revoked_at)
      )
      |> select([pass], pass)
      |> Repo.update_all(set: [last_updated_at: at, updated_at: at])

    Enum.map(passes, &normalize/1)
  end

  @impl true
  def list_user_passes(_context, user_id) do
    from(pass in WalletPass,
      left_join: organization in "organizations",
      on: organization.id == pass.organization_id,
      where: pass.user_id == ^user_id,
      order_by: [desc: pass.inserted_at],
      select: %{
        pass: pass,
        organization_slug: organization.slug,
        organization_name: organization.name
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      row.pass
      |> normalize()
      |> Map.merge(%{
        organization_slug: row.organization_slug,
        organization_name: row.organization_name
      })
    end)
  end

  @impl true
  def register_device(_context, pass_id, device, push_token) do
    case Repo.get_by(DeviceRegistration, pass_id: pass_id, device_library_id: device) do
      nil ->
        %{pass_id: pass_id, device_library_id: device, push_token: push_token}
        |> DeviceRegistration.changeset()
        |> Repo.insert()
        |> case do
          {:ok, _registration} -> {:ok, :created}
          {:error, changeset} -> {:error, changeset}
        end

      registration ->
        registration
        |> DeviceRegistration.changeset(%{push_token: push_token})
        |> Repo.update()
        |> case do
          {:ok, _registration} -> {:ok, :existing}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def unregister_device(_context, pass_id, device) do
    DeviceRegistration
    |> where([r], r.pass_id == ^pass_id and r.device_library_id == ^device)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def push_tokens(_context, pass_id) do
    DeviceRegistration
    |> where([r], r.pass_id == ^pass_id)
    |> select([r], r.push_token)
    |> distinct(true)
    |> Repo.all()
  end

  @impl true
  def forget_push_token(_context, token) do
    DeviceRegistration
    |> where([r], r.push_token == ^token)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def pass_organization(serial) when is_binary(serial) do
    case Repo.query!("SELECT palee_wallet_pass_organization($1)", [serial]) do
      %{rows: [[id]]} when is_binary(id) -> Ecto.UUID.load!(id)
      _missing -> nil
    end
  end

  def pass_organization(_serial), do: nil

  @impl true
  def device_serials(device, since) do
    since = since && DateTime.to_naive(since)

    %{rows: rows} =
      Repo.query!("SELECT serial, last_updated_at FROM palee_wallet_device_serials($1, $2)", [
        device,
        since
      ])

    Enum.map(rows, fn [serial, at] -> {serial, DateTime.from_naive!(at, "Etc/UTC")} end)
  end

  defp normalize_result({:ok, pass}), do: {:ok, normalize(pass)}
  defp normalize_result(error), do: error

  defp normalize(nil), do: nil

  defp normalize(%WalletPass{} = pass) do
    Map.take(pass, [
      :id,
      :organization_id,
      :user_id,
      :member_code_id,
      :platform,
      :serial,
      :auth_token_hash,
      :revoked_at,
      :last_updated_at,
      :inserted_at
    ])
  end
end
