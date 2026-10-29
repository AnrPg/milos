defmodule Palee.Application.Documents.DocumentsAdmin do
  @moduledoc """
  Staff › Documents (ADR-252): documents and their versions, which are
  mandatory, signature requests (one person or in bulk), signatures and
  their certificates, a client's documents, the box's settings and the
  audit log.
  """

  alias Palee.Application.Documents.DocumentViews, as: V
  alias Palee.{Documents, Finance, Notifications, Organizations}

  @client_roles ~w(member athlete)

  # ── Documents ───────────────────────────────────────────────────────────

  def list_templates(context, params) do
    filters =
      %{status: param(params, :status), requirement: param(params, :requirement)}
      |> compact()

    %{templates: context |> Documents.list_templates(filters) |> Enum.map(&V.template/1)}
  end

  def starters(params), do: %{starters: Documents.starter_templates(param(params, :language))}

  def create_template(context, params, now \\ DateTime.utc_now()) do
    attrs = %{
      kind: param(params, :kind),
      title: param(params, :title),
      requirement: param(params, :requirement),
      body: param(params, :body),
      language: param(params, :language)
    }

    with {:ok, %{template: template, version: version}} <-
           Documents.create_template(context, attrs, context.user_id, now) do
      {:ok, %{template: V.template(template), version: V.version(version)}}
    end
  end

  def get_template(context, id) do
    with {:ok, template} <- Documents.get_template_with_versions(context, id) do
      current = template.current_version_id && Documents.get_version(context, template.current_version_id)
      {:ok, %{template: V.template(template), current_version: current && V.version(current)}}
    end
  end

  def get_version(context, template_id, version_id) do
    case Documents.get_version(context, version_id) do
      %{template_id: ^template_id} = version -> {:ok, %{version: V.version(version)}}
      _ -> {:error, :not_found}
    end
  end

  def publish_version(context, template_id, params, now \\ DateTime.utc_now()) do
    attrs = %{
      title: param(params, :title),
      body: param(params, :body),
      language: param(params, :language),
      change_kind: param(params, :change_kind)
    }

    with {:ok, %{template: template, version: version}} <-
           Documents.publish_version(context, template_id, compact(attrs), context.user_id, now) do
      {:ok, %{template: V.template(template), version: V.version(version)}}
    end
  end

  def set_requirement(context, template_id, params, now \\ DateTime.utc_now()) do
    with {:ok, template} <-
           Documents.set_requirement(
             context,
             template_id,
             param(params, :requirement),
             context.user_id,
             now
           ) do
      {:ok, %{template: V.template(template)}}
    end
  end

  def archive_template(context, template_id, now \\ DateTime.utc_now()) do
    with {:ok, template} <- Documents.archive_template(context, template_id, context.user_id, now) do
      {:ok, %{template: V.template(template)}}
    end
  end

  # ── Requests ────────────────────────────────────────────────────────────

  @doc """
  Asks clients to sign a document: `audience` `person` (`user_id`),
  `all_clients`, `role` (`role`: member or athlete) or `package`
  (`package_id`: clients whose subscription to it is current). Each new
  request notifies its client.
  """
  def request_signatures(context, template_id, params, now \\ DateTime.utc_now()) do
    audience = param(params, :audience) || "person"

    with {:ok, user_ids} <- recipients(context, audience, params, now),
         {:ok, result} <-
           Documents.request_signatures(context, template_id, user_ids, audience, context.user_id, now) do
      notify(context, result)

      {:ok,
       %{
         batch_id: result.batch_id,
         audience: audience,
         recipients: length(user_ids),
         created: length(result.requests),
         skipped: result.skipped,
         requests: Enum.map(result.requests, &V.request/1)
       }}
    end
  end

  defp recipients(context, "person", params, _now) do
    user_id = param(params, :user_id)

    if is_binary(user_id) and Organizations.client_role(context, user_id),
      do: {:ok, [user_id]},
      else: {:error, {:invalid_fields, %{user_id: "not_a_client"}}}
  end

  defp recipients(context, "all_clients", _params, _now),
    do: {:ok, Organizations.list_client_user_ids(context)}

  defp recipients(context, "role", params, _now) do
    role = param(params, :role)

    if role in @client_roles do
      {:ok,
       context
       |> Organizations.member_roles_by_user()
       |> Enum.filter(fn {_user_id, facts} -> String.to_existing_atom(role) in facts.roles end)
       |> Enum.map(&elem(&1, 0))}
    else
      {:error, {:invalid_fields, %{role: "invalid"}}}
    end
  end

  defp recipients(context, "package", params, now) do
    package_id = param(params, :package_id)

    with {:ok, _package} <- package(context, package_id) do
      clients = MapSet.new(Organizations.list_client_user_ids(context))

      holders =
        Finance.package_holder_user_ids(
          context,
          package_id,
          Organizations.local_date(context, now)
        )

      {:ok, Enum.filter(holders, &MapSet.member?(clients, &1))}
    end
  end

  defp recipients(_context, _audience, _params, _now),
    do: {:error, {:invalid_fields, %{audience: "invalid"}}}

  defp package(context, package_id) when is_binary(package_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(package_id),
         %{} = package <- Finance.get_package(context, package_id) do
      {:ok, package}
    else
      _ -> {:error, {:invalid_fields, %{package_id: "not_found"}}}
    end
  end

  defp package(_context, _package_id), do: {:error, {:invalid_fields, %{package_id: "required"}}}

  defp notify(context, %{template: template, requests: requests}) do
    Enum.each(requests, fn request ->
      Notifications.dispatch_event(:document_signature_requested, %{
        user_id: request.user_id,
        organization_id: context.organization_id,
        template_id: template.id,
        title: template.title,
        business_name: business_name(context),
        dedupe_key: "document_signature_requested:#{request.id}"
      })
    end)
  end

  def list_requests(context, params) do
    filters =
      %{
        status: param(params, :status),
        template_id: param(params, :template_id),
        user_id: param(params, :user_id),
        batch_id: param(params, :batch_id),
        limit: integer(param(params, :limit)),
        offset: integer(param(params, :offset))
      }
      |> compact()

    result = Documents.list_requests(context, filters)
    %{requests: Enum.map(result.requests, &V.request/1), total: result.total}
  end

  def cancel_request(context, request_id, now \\ DateTime.utc_now()) do
    with {:ok, request} <- Documents.cancel_request(context, request_id, context.user_id, now) do
      {:ok, %{request: V.request(request)}}
    end
  end

  # ── Signatures ──────────────────────────────────────────────────────────

  def list_signatures(context, params) do
    filters =
      %{
        template_id: param(params, :template_id),
        user_id: param(params, :user_id),
        limit: integer(param(params, :limit)),
        offset: integer(param(params, :offset))
      }
      |> compact()

    result = Documents.list_signatures(context, filters)
    %{signatures: Enum.map(result.signatures, &V.signature/1), total: result.total}
  end

  @doc "A short-lived link to a signature's PDF certificate (the download is audited)."
  def evidence(context, signature_id, now \\ DateTime.utc_now()) do
    with %{} = signature <- Documents.get_signature(context, signature_id) || {:error, :not_found},
         {:ok, url} <- evidence_url(context, signature),
         {:ok, _event} <-
           Documents.audit(
             context,
             "evidence_downloaded",
             "document_signature",
             signature.id,
             context.user_id,
             now,
             %{},
             signature.user_id
           ) do
      {:ok, %{url: url, sha256: signature.evidence_sha256, byte_size: signature.evidence_byte_size}}
    end
  end

  def evidence_url(context, signature) do
    case Documents.evidence_url(context, signature) do
      {:ok, url} -> {:ok, url}
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  @doc """
  A client's documents for their profile: every document with its status,
  their signatures and their health certificate status.
  """
  def member(context, user_id, now \\ DateTime.utc_now()) do
    if Organizations.client_role(context, user_id) do
      items = Documents.member_items(context, user_id)
      health = Documents.health_status(context, user_id, Organizations.local_date(context, now))

      {:ok,
       %{
         user_id: user_id,
         documents: Enum.map(items, &V.item/1),
         outstanding: Enum.count(items, & &1.outstanding),
         signatures:
           Enum.map(Documents.list_signatures(context, %{user_id: user_id}).signatures, &V.signature/1),
         health_certificate_status: health.status
       }}
    else
      {:error, :not_found}
    end
  end

  # ── Settings and audit ──────────────────────────────────────────────────

  def settings(context), do: %{settings: Documents.settings(context)}

  def save_settings(context, params, now \\ DateTime.utc_now()) do
    changes =
      Documents.settings(context)
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        case param(params, field) do
          nil -> acc
          value -> Map.put(acc, field, value)
        end
      end)

    with {:ok, settings} <- Documents.save_settings(context, changes, context.user_id, now) do
      {:ok, %{settings: settings}}
    end
  end

  def audit_events(context, params) do
    filters =
      %{
        subject_id: param(params, :subject_id),
        action: param(params, :action),
        limit: integer(param(params, :limit)),
        offset: integer(param(params, :offset))
      }
      |> compact()

    result = Documents.list_audit_events(context, filters)
    %{events: Enum.map(result.events, &V.event/1), total: result.total}
  end

  @doc "The box's name, as printed on certificates and notifications."
  def business_name(%{organization: %{name: name}}), do: name
  def business_name(_context), do: nil

  defp compact(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp param(_params, _key), do: nil

  defp integer(value) when is_integer(value) and value >= 0, do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  defp integer(_value), do: nil
end
