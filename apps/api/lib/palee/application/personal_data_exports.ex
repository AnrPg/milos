defmodule Palee.Application.PersonalDataExports do
  @moduledoc """
  ADR-267: «Λήψη των δεδομένων μου» / "Download my data" (GDPR articles 15
  and 20), from Settings.

  1. `request/2` (`POST /api/me/data-exports`) records a request, at most
     one in progress and one a day (`ExportPolicy`), and queues
     `PersonalDataExportJob`.
  2. The job (`build/3`) gathers the profile's own rows across contexts in
     the profile's own sessions (`PersonalData.collect/1`: row-level security
     applies, other people's data and secrets are left out), writes one ZIP
     of JSON files privately under the profile's storage prefix and emails a
     notice through the outbox. The email carries no download link: it sends
     the person to Settings, where they are signed in.
  3. `list/2` (`GET /api/me/data-exports`) shows the requests; a ready file
     gets a short-lived presigned download link, made afresh on every call,
     until it expires after `ExportPolicy.keep_days/0` days.
  """

  require Logger

  alias Palee.{Email, Identity, PersonalData}
  alias Palee.Application.{MediaStorage, PublicURL}
  alias Palee.Workers.PersonalDataExportJob

  @bucket :media_private
  @content_type "application/zip"

  @doc "Asks for a new export of the signed-in profile's data."
  def request(%{user_id: user_id}, now \\ DateTime.utc_now()) do
    with :ok <- PersonalData.can_request?(PersonalData.list_exports(user_id), now),
         {:ok, export} <- insert(user_id, now) do
      :ok = enqueue(user_id, export.id)
      {:ok, view(user_id, PersonalData.get_export(export.id, user_id) || export, now)}
    end
  end

  @doc "The profile's requests, newest first, with download links for live files."
  def list(%{user_id: user_id}, now \\ DateTime.utc_now()) do
    {:ok, user_id |> PersonalData.list_exports() |> Enum.map(&view(user_id, &1, now))}
  end

  @doc "Builds one export (the job's work)."
  def build(user_id, export_id, now \\ DateTime.utc_now()) do
    case PersonalData.get_export(export_id, user_id) do
      %{status: "pending"} = export -> run(user_id, export, now)
      nil -> {:ok, :gone}
      _done -> {:ok, :skipped}
    end
  end

  @doc "Marks an export failed for good (the job's last attempt): the person may ask again."
  def fail(user_id, export_id, reason) do
    case PersonalData.get_export(export_id, user_id) do
      %{status: "pending"} = export ->
        PersonalData.finish_export(export, %{
          status: "failed",
          error: reason |> inspect() |> String.slice(0, 500)
        })

      _other ->
        {:ok, :skipped}
    end
  end

  # -- building ------------------------------------------------------------------

  defp run(user_id, export, now) do
    sections = PersonalData.collect(user_id)
    owner = MediaStorage.owner(%{user_id: user_id}, :account)
    name = PersonalData.file_name(now)
    key = MediaStorage.object_key(owner, "exports/personal-data/#{export.id}/#{name}")

    with {:ok, %{zip: zip, record_count: count}} <-
           PersonalData.archive(user_id, sections, now),
         :ok <- store(owner, key, zip),
         {:ok, finished} <-
           PersonalData.finish_export(export, %{
             status: "ready",
             record_count: count,
             file: %{
               "name" => name,
               "key" => key,
               "bytes" => byte_size(zip),
               "sha256" => Base.encode16(:crypto.hash(:sha256, zip), case: :lower)
             },
             completed_at: now,
             expires_at: PersonalData.expires_at(now)
           }) do
      :ok = notify(user_id, finished, now)
      {:ok, finished}
    end
  end

  defp store(owner, key, zip) do
    case MediaStorage.put(owner, @bucket, key, zip, @content_type) do
      :ok -> :ok
      {:ok, _stored} -> :ok
      {:error, _reason} = error -> error
    end
  end

  # The email outbox (ADR-203) sends it; a person without an address gets the
  # file in Settings all the same.
  defp notify(user_id, export, now) do
    case Identity.find_by_id(user_id) do
      %{email: email} = account when is_binary(email) ->
        result =
          Email.enqueue(
            :personal_data_export_ready,
            email,
            %{
              url: PublicURL.base_url() <> "/me/settings#your-data",
              expires_at: export.expires_at,
              keep_days: PersonalData.keep_days()
            },
            locale: account.preferred_locale || "en",
            login_id: account.login_id,
            user_id: user_id,
            idempotency_key: "personal_data_export:#{export.id}:ready",
            now: now
          )

        case result do
          {:error, reason} ->
            Logger.warning(
              "personal data export #{export.id}: notice not queued: #{inspect(reason)}"
            )

          _queued ->
            :ok
        end

        :ok

      _none ->
        :ok
    end
  end

  # -- shapes --------------------------------------------------------------------

  defp insert(user_id, now) do
    case PersonalData.insert_export(%{user_id: user_id, requested_at: now}) do
      {:ok, export} ->
        {:ok, export}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :user_id),
          do: {:error, :export_in_progress},
          else: {:error, changeset}
    end
  end

  defp view(user_id, export, now) do
    downloadable? = PersonalData.downloadable?(export, now)

    %{
      id: export.id,
      status: PersonalData.visible_status(export, now),
      record_count: export.record_count,
      requested_at: export.requested_at,
      completed_at: export.completed_at,
      expires_at: export.expires_at,
      file: if(downloadable?, do: file(user_id, export.file))
    }
  end

  defp file(user_id, %{"key" => key} = file) do
    owner = MediaStorage.owner(%{user_id: user_id}, :account)

    url =
      case MediaStorage.read_url(owner, @bucket, key) do
        {:ok, url} -> url
        _error -> nil
      end

    %{name: file["name"], bytes: file["bytes"], sha256: file["sha256"], download_url: url}
  end

  defp file(_user_id, _file), do: nil

  defp enqueue(user_id, export_id) do
    if Application.get_env(:palee, :start_oban, true) do
      {:ok, _job} =
        %{"user_id" => user_id, "export_id" => export_id}
        |> PersonalDataExportJob.new()
        |> Oban.insert()

      :ok
    else
      _result = build(user_id, export_id)
      :ok
    end
  rescue
    error ->
      Logger.error(
        "personal data export enqueue failed export_id=#{export_id} error=#{inspect(error)}"
      )

      :ok
  end
end
