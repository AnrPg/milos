defmodule Palee.Application.Documents.HealthCertificatesAdmin do
  @moduledoc """
  Staff › Documents › health certificates (ADR-252, GDPR art. 9).

  Staff with `manage_health_certificates` see every client's certificate
  dates, open the file (each look is audited), upload one on a client's
  behalf and delete one. Staff who only hold `view_health` (coaches, for
  their own clients) see a status and nothing else: valid, expired or
  missing.
  """

  alias Palee.Application.AuthorizeClientAccess
  alias Palee.Application.Documents.DocumentViews, as: V
  alias Palee.Application.Documents.HealthCertificateFiles, as: Files
  alias Palee.{Documents, Identity, Organizations}

  @statuses ~w(missing valid expiring expired)

  @doc "Every client (or the actor's own clients) with their certificate status."
  def list(context, params, now \\ DateTime.utc_now()) do
    today = Organizations.local_date(context, now)
    full? = manager?(context)

    clients =
      case if(full?, do: :all, else: AuthorizeClientAccess.client_ids(context, :view_health)) do
        :all -> Organizations.list_client_user_ids(context)
        ids -> MapSet.intersection(MapSet.new(ids), MapSet.new(Organizations.list_client_user_ids(context))) |> MapSet.to_list()
      end

    statuses = Documents.health_statuses(context, clients, today)
    names = clients |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
    wanted = Files.param(params, :status)

    rows =
      clients
      |> Enum.map(fn user_id ->
        %{status: status, certificate: certificate} = Map.fetch!(statuses, user_id)
        row(user_id, Map.get(names, user_id), status, certificate, full?)
      end)
      |> Enum.filter(&(wanted not in @statuses or &1.status == wanted))
      |> Enum.sort_by(&{status_rank(&1.status), &1.display_name || ""})

    %{
      health_certificates: rows,
      required: Documents.settings(context).health_certificate_required,
      full_access: full?
    }
  end

  defp row(user_id, account, status, certificate, true) do
    %{
      user_id: user_id,
      display_name: account && account.nickname,
      handle: account && account.handle,
      status: status,
      certificate: V.certificate(certificate)
    }
  end

  defp row(user_id, account, status, _certificate, false) do
    %{
      user_id: user_id,
      display_name: account && account.nickname,
      handle: account && account.handle,
      status: V.coach_status(status),
      certificate: nil
    }
  end

  defp status_rank("expired"), do: 0
  defp status_rank("missing"), do: 1
  defp status_rank("expiring"), do: 2
  defp status_rank(_valid), do: 3

  @doc "A client's certificates, newest first (full access only)."
  def for_client(context, user_id) do
    with :ok <- client(context, user_id) do
      {:ok,
       %{
         user_id: user_id,
         health_certificates:
           context |> Documents.list_health_certificates(user_id) |> Enum.map(&V.certificate/1)
       }}
    end
  end

  def request_upload(context, params) do
    user_id = Files.param(params, :user_id)

    with :ok <- client(context, user_id) do
      Files.request_upload(context, user_id, Files.param(params, :content_type))
    end
  end

  def complete_upload(context, params, now \\ DateTime.utc_now()) do
    user_id = Files.param(params, :user_id)

    with :ok <- client(context, user_id),
         {:ok, certificate} <- Files.complete(context, user_id, params, context.user_id, now) do
      {:ok, %{health_certificate: V.certificate(certificate)}}
    end
  end

  def download(context, id, now \\ DateTime.utc_now()) do
    with %{} = certificate <- Documents.get_health_certificate(context, id) || {:error, :not_found} do
      Files.download(context, certificate, context.user_id, now)
    end
  end

  def delete(context, id, now \\ DateTime.utc_now()) do
    with %{} = certificate <- Documents.get_health_certificate(context, id) || {:error, :not_found},
         {:ok, deleted} <- Files.delete(context, certificate, context.user_id, now) do
      {:ok, %{health_certificate: V.certificate(deleted)}}
    end
  end

  defp manager?(context),
    do: Organizations.capability_scope(context, :manage_health_certificates) == :all

  defp client(context, user_id) when is_binary(user_id) do
    if Organizations.client_role(context, user_id), do: :ok, else: {:error, :not_found}
  end

  defp client(_context, _user_id), do: {:error, {:invalid_fields, %{user_id: "required"}}}
end
