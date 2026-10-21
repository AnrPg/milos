defmodule Palee.Infrastructure.Facility.EctoFacilityStore do
  @moduledoc "Ecto adapter of the Facility store (ADR-097)."

  @behaviour Palee.Facility.Ports.FacilityStore

  import Ecto.Query

  alias Palee.Facility.{CheckIn, CheckInSettings, Location, MemberCodeRecord, VisitorScan}
  alias Palee.Repo

  @impl true
  def list_locations(%{organization_id: organization_id}, opts) do
    Location
    |> where([location], location.organization_id == ^organization_id)
    |> maybe_active(Keyword.get(opts, :include_archived, false))
    |> order_by([location], asc: location.name)
    |> Repo.all()
    |> Enum.map(&normalize_location/1)
  end

  @impl true
  def get_location(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Location{} = location <-
           Repo.get_by(Location, id: id, organization_id: organization_id) do
      normalize_location(location)
    else
      _missing -> nil
    end
  end

  @impl true
  def create_location(%{organization_id: organization_id}, params) do
    params
    |> string_keys()
    |> Map.put("organization_id", organization_id)
    |> Location.create_changeset()
    |> Repo.insert()
    |> normalize_result(&normalize_location/1)
  end

  @impl true
  def update_location(%{organization_id: organization_id}, id, params) do
    case fetch_location(organization_id, id) do
      nil ->
        {:error, :not_found}

      location ->
        location
        |> Location.update_changeset(string_keys(params))
        |> Repo.update()
        |> normalize_result(&normalize_location/1)
    end
  end

  @impl true
  def archive_location(%{organization_id: organization_id}, id) do
    case fetch_location(organization_id, id) do
      nil ->
        {:error, :not_found}

      %Location{archived_at: nil} = location ->
        location
        |> Location.archive_changeset(DateTime.utc_now())
        |> Repo.update()
        |> normalize_result(&normalize_location/1)

      location ->
        {:ok, normalize_location(location)}
    end
  end

  @impl true
  def get_check_in(%{organization_id: organization_id}, user_id, %Date{} = date) do
    CheckIn
    |> where(
      [check_in],
      check_in.organization_id == ^organization_id and check_in.user_id == ^user_id and
        check_in.checked_in_on == ^date
    )
    |> check_in_query()
    |> Repo.one()
  end

  @impl true
  def create_check_in(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> CheckIn.changeset()
    |> Repo.insert()
    |> case do
      {:ok, check_in} ->
        {:ok,
         get_check_in(
           %{organization_id: organization_id},
           check_in.user_id,
           check_in.checked_in_on
         )}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @impl true
  def list_check_ins(%{organization_id: organization_id}, filters) do
    CheckIn
    |> where([check_in], check_in.organization_id == ^organization_id)
    |> maybe_filter(:checked_in_on, filters[:date])
    |> maybe_filter(:user_id, filters[:user_id])
    |> maybe_filter(:location_id, filters[:location_id])
    |> maybe_since(filters[:since])
    |> check_in_query()
    |> order_by([check_in], desc: check_in.checked_in_at)
    |> limit(^min(filters[:limit] || 200, 500))
    |> Repo.all()
  end

  defp check_in_query(query) do
    from check_in in query,
      left_join: user in "users",
      on: user.id == check_in.user_id,
      left_join: location in Location,
      on: location.id == check_in.location_id,
      select: %{
        id: check_in.id,
        organization_id: check_in.organization_id,
        user_id: check_in.user_id,
        nickname: user.nickname,
        location_id: check_in.location_id,
        location_name: location.name,
        checked_in_on: check_in.checked_in_on,
        checked_in_at: check_in.checked_in_at,
        source: check_in.source,
        method: check_in.method,
        recorded_by_id: check_in.recorded_by_id,
        reservation_id: check_in.reservation_id,
        display_name: coalesce(user.display_nickname, user.nickname),
        avatar_url: user.avatar_url
      }
  end

  defp maybe_since(query, nil), do: query

  defp maybe_since(query, %DateTime{} = since),
    do: where(query, [check_in], check_in.checked_in_at >= ^since)

  @impl true
  def get_check_in_by_id(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      CheckIn
      |> where([check_in], check_in.organization_id == ^organization_id and check_in.id == ^id)
      |> check_in_query()
      |> Repo.one()
    else
      :error -> nil
    end
  end

  @impl true
  def delete_check_in(%{organization_id: organization_id}, id) do
    case Repo.get_by(CheckIn, id: id, organization_id: organization_id) do
      nil -> {:error, :not_found}
      check_in -> Repo.delete(check_in)
    end
  end

  @impl true
  def get_door_secret(%{organization_id: organization_id}, location_id) do
    case fetch_location(organization_id, location_id) do
      %Location{door_secret: secret} -> secret
      nil -> nil
    end
  end

  @impl true
  def rotate_door_secret(%{organization_id: organization_id}, location_id, secret, at) do
    case fetch_location(organization_id, location_id) do
      nil ->
        {:error, :location_not_found}

      location ->
        location
        |> Location.rotate_door_changeset(secret, at)
        |> Repo.update()
        |> normalize_result(&normalize_location/1)
    end
  end

  @impl true
  def get_check_in_settings(%{organization_id: organization_id}) do
    case Repo.get_by(CheckInSettings, organization_id: organization_id) do
      nil -> nil
      settings -> normalize_settings(settings)
    end
  end

  @impl true
  def put_check_in_settings(%{organization_id: organization_id}, changes) do
    (Repo.get_by(CheckInSettings, organization_id: organization_id) ||
       %CheckInSettings{organization_id: organization_id})
    |> CheckInSettings.changeset(Map.put(changes, :organization_id, organization_id))
    |> Repo.insert_or_update()
    |> normalize_result(&normalize_settings/1)
  end

  @impl true
  def record_visitor_scan(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> VisitorScan.changeset()
    |> Repo.insert()
  end

  @impl true
  def list_visitor_scans(%{organization_id: organization_id}, filters) do
    from(scan in VisitorScan,
      left_join: user in "users",
      on: user.id == scan.user_id,
      left_join: location in Location,
      on: location.id == scan.location_id,
      where: scan.organization_id == ^organization_id,
      order_by: [desc: scan.scanned_at],
      limit: ^min(filters[:limit] || 100, 500),
      select: %{
        id: scan.id,
        user_id: scan.user_id,
        nickname: user.nickname,
        display_name: coalesce(user.display_nickname, user.nickname),
        avatar_url: user.avatar_url,
        location_id: scan.location_id,
        location_name: location.name,
        scanned_at: scan.scanned_at,
        trial_offered: scan.trial_offered
      }
    )
    |> scan_filter(:from, filters[:from])
    |> scan_filter(:to, filters[:to])
    |> scan_filter(:location_id, filters[:location_id])
    |> Repo.all()
  end

  @impl true
  def get_poster(%{organization_id: organization_id}, location_id) do
    case fetch_location(organization_id, location_id) do
      %Location{} = location ->
        %{
          location_id: location.id,
          enabled: location.poster_enabled,
          secret: location.poster_secret,
          rotated_at: location.poster_secret_rotated_at,
          archived_at: location.archived_at
        }

      nil ->
        nil
    end
  end

  @impl true
  def rotate_poster_secret(%{organization_id: organization_id}, location_id, secret, at) do
    update_location_with(
      organization_id,
      location_id,
      &Location.rotate_poster_changeset(&1, secret, at)
    )
  end

  @impl true
  def set_poster_enabled(%{organization_id: organization_id}, location_id, enabled) do
    update_location_with(organization_id, location_id, &Location.poster_changeset(&1, enabled))
  end

  @impl true
  def get_nfc_tag(%{organization_id: organization_id}, location_id) do
    case fetch_location(organization_id, location_id) do
      %Location{} = location ->
        %{
          location_id: location.id,
          enabled: location.nfc_enabled,
          secret: location.nfc_secret,
          rotated_at: location.nfc_secret_rotated_at,
          archived_at: location.archived_at
        }

      nil ->
        nil
    end
  end

  @impl true
  def rotate_nfc_secret(%{organization_id: organization_id}, location_id, secret, at) do
    update_location_with(
      organization_id,
      location_id,
      &Location.rotate_nfc_changeset(&1, secret, at)
    )
  end

  @impl true
  def set_nfc_enabled(%{organization_id: organization_id}, location_id, enabled) do
    update_location_with(organization_id, location_id, &Location.nfc_changeset(&1, enabled))
  end

  defp update_location_with(organization_id, location_id, changeset) do
    case fetch_location(organization_id, location_id) do
      nil ->
        {:error, :location_not_found}

      location ->
        location
        |> changeset.()
        |> Repo.update()
        |> normalize_result(&normalize_location/1)
    end
  end

  @impl true
  def get_active_member_code(%{organization_id: organization_id}, user_id) do
    MemberCodeRecord
    |> where([code], code.organization_id == ^organization_id and code.user_id == ^user_id)
    |> where([code], is_nil(code.revoked_at))
    |> limit(1)
    |> Repo.one()
  end

  @impl true
  def get_member_code(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(MemberCodeRecord, id: id, organization_id: organization_id)
      :error -> nil
    end
  end

  @impl true
  def get_member_code_by_serial(%{organization_id: organization_id}, serial) do
    case Ecto.UUID.cast(serial) do
      {:ok, serial} ->
        Repo.get_by(MemberCodeRecord, serial: serial, organization_id: organization_id)

      :error ->
        nil
    end
  end

  @impl true
  def create_member_code(_context, attrs),
    do: attrs |> MemberCodeRecord.create_changeset() |> Repo.insert()

  @impl true
  def revoke_member_codes(%{organization_id: organization_id}, filters, reason, at) do
    query =
      MemberCodeRecord
      |> where([code], code.organization_id == ^organization_id and is_nil(code.revoked_at))
      |> then(fn query ->
        case filters[:user_id] do
          nil -> query
          user_id -> where(query, [code], code.user_id == ^user_id)
        end
      end)
      |> select([code], code)

    {_count, codes} =
      Repo.update_all(query, set: [revoked_at: at, revoked_reason: reason, updated_at: at])

    codes
  end

  defp scan_filter(query, _key, nil), do: query
  defp scan_filter(query, :from, from), do: where(query, [scan], scan.scanned_at >= ^from)
  defp scan_filter(query, :to, to), do: where(query, [scan], scan.scanned_at < ^to)

  defp scan_filter(query, :location_id, id),
    do: where(query, [scan], scan.location_id == ^id)

  @impl true
  def door_location(location_id) do
    with {:ok, binary} <- Ecto.UUID.dump(location_id),
         %{rows: [[organization_id, slug, name, logo_url, color, location_name]]} <-
           Repo.query!(
             "SELECT organization_id, slug, name, logo_url, primary_color, location_name FROM palee_door_location($1)",
             [binary]
           ) do
      %{
        organization_id: Ecto.UUID.load!(organization_id),
        location_id: location_id,
        slug: slug,
        name: name,
        logo_url: logo_url,
        primary_color: color,
        location_name: location_name
      }
    else
      _missing -> nil
    end
  end

  defp normalize_settings(%CheckInSettings{} = settings),
    do: Map.take(settings, Palee.Facility.Domain.CheckInRules.fields())

  defp maybe_active(query, true), do: query
  defp maybe_active(query, _), do: where(query, [location], is_nil(location.archived_at))

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value),
    do: where(query, [check_in], field(check_in, ^field) == ^value)

  defp fetch_location(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(Location, id: id, organization_id: organization_id)
      :error -> nil
    end
  end

  defp normalize_result({:ok, record}, normalize), do: {:ok, normalize.(record)}
  defp normalize_result({:error, changeset}, _normalize), do: {:error, changeset}

  defp normalize_location(%Location{} = location) do
    %{
      id: location.id,
      organization_id: location.organization_id,
      name: location.name,
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
      neighbourhood: location.neighbourhood,
      city: location.city,
      country_code: location.country_code,
      opening_hours: location.opening_hours,
      accessibility: location.accessibility,
      archived_at: location.archived_at,
      door_secret_rotated_at: location.door_secret_rotated_at,
      poster_enabled: location.poster_enabled,
      poster_secret_rotated_at: location.poster_secret_rotated_at,
      nfc_enabled: location.nfc_enabled,
      nfc_secret_rotated_at: location.nfc_secret_rotated_at,
      inserted_at: location.inserted_at,
      updated_at: location.updated_at
    }
  end

  defp string_keys(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end
