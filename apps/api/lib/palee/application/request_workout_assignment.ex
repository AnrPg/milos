defmodule Palee.Application.RequestWorkoutAssignment do
  alias Palee.{Notifications, Organizations}

  def call(context, athlete, params) when is_map(params) do
    with :ok <- authorize_tenant_athlete(context, athlete),
         {:ok, requested_for} <-
           parse_requested_for(params["requested_for"] || params[:requested_for]),
         :ok <- reject_past_date(requested_for, context),
         admin_ids when admin_ids != [] <-
           Organizations.list_staff_user_ids(context.organization_id),
         :ok <- notify_admins(context, athlete, requested_for, params, admin_ids) do
      {:ok, %{requested_for: requested_for, notified_admins: length(admin_ids)}}
    else
      [] -> {:error, :no_admins}
      {:error, reason} -> {:error, reason}
    end
  end

  def call(_context, _user, _params), do: {:error, :forbidden}
  def call(_user, _params), do: {:error, :organization_context_required}

  defp authorize_tenant_athlete(%{organization_id: organization_id}, athlete) do
    athlete.id
    |> Organizations.list_memberships()
    |> Enum.any?(fn %{membership: membership, organization: organization} ->
      organization.id == organization_id and membership.role == :athlete
    end)
    |> if(do: :ok, else: {:error, :forbidden})
  end

  defp authorize_tenant_athlete(_context, _athlete), do: {:error, :forbidden}

  defp parse_requested_for(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :bad_request}
    end
  end

  defp parse_requested_for(%Date{} = date), do: {:ok, date}
  defp parse_requested_for(_value), do: {:error, :bad_request}

  # ADR-177: "the past" is before the gym's today.
  defp reject_past_date(date, context) do
    if Date.compare(date, Organizations.local_today(context.organization_id)) == :lt do
      {:error, :past_date}
    else
      :ok
    end
  end

  defp notify_admins(context, athlete, requested_for, params, admin_ids) do
    note = params["note"] || params[:note]

    Notifications.dispatch_event(:workout_assignment_requested, %{
      request_id: Ecto.UUID.generate(),
      organization_id: context && Map.get(context, :organization_id),
      admin_ids: admin_ids,
      athlete_id: athlete.id,
      athlete_nickname: athlete.nickname,
      requested_for: Date.to_iso8601(requested_for),
      note: normalize_note(note)
    })
  end

  defp normalize_note(note) when is_binary(note) do
    note
    |> String.trim()
    |> case do
      "" -> nil
      value -> String.slice(value, 0, 500)
    end
  end

  defp normalize_note(_note), do: nil
end
