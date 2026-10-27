defmodule Palee.Infrastructure.Identity.EctoLoginDeviceStore do
  @moduledoc "Postgres storage of the devices a login has signed in from (ADR-208)."
  @behaviour Palee.Identity.Ports.LoginDeviceStore

  import Ecto.Query

  alias Palee.Identity.{Login, LoginDevice}
  alias Palee.Repo

  # The newest devices kept per login; older ones are forgotten (and would
  # alert again, which is the safe side).
  @keep_per_login 30

  @impl true
  def remember(login_id, device_hash, description, source, now) do
    # The login row serialises two racing sign-ins of one login, so they
    # agree on whether the device is new.
    Repo.transaction(fn ->
      case Login
           |> where([l], l.id == ^login_id)
           |> lock("FOR UPDATE")
           |> select([l], l.id)
           |> Repo.one() do
        nil -> :known
        _id -> remember_locked(login_id, device_hash, description, source, now)
      end
    end)
    |> case do
      {:ok, outcome} -> outcome
      {:error, _reason} -> :known
    end
  end

  defp remember_locked(login_id, device_hash, description, source, now) do
    increment = if source == :sign_in, do: 1, else: 0

    case Repo.get_by(LoginDevice, login_id: login_id, device_hash: device_hash) do
      %LoginDevice{} = device ->
        LoginDevice
        |> where([d], d.id == ^device.id)
        |> Repo.update_all(
          set: [last_seen_at: now, client: description[:client], platform: description[:platform]],
          inc: [sign_ins: increment]
        )

        :known

      nil ->
        signed_in_before? =
          LoginDevice
          |> where([d], d.login_id == ^login_id and d.sign_ins > 0)
          |> Repo.exists?()

        Repo.insert!(%LoginDevice{
          login_id: login_id,
          device_hash: device_hash,
          client: description[:client],
          platform: description[:platform],
          sign_ins: increment,
          first_seen_at: now,
          last_seen_at: now
        })

        prune(login_id)

        cond do
          source == :sign_up -> :first
          signed_in_before? -> :new
          true -> :first
        end
    end
  end

  defp prune(login_id) do
    keep =
      LoginDevice
      |> where([d], d.login_id == ^login_id)
      |> order_by([d], desc: d.last_seen_at)
      |> limit(@keep_per_login)
      |> select([d], d.id)

    LoginDevice
    |> where([d], d.login_id == ^login_id and d.id not in subquery(keep))
    |> Repo.delete_all()
  end
end
