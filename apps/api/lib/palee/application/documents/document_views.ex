defmodule Palee.Application.Documents.DocumentViews do
  @moduledoc """
  What the Documents endpoints show (ADR-252). A health certificate's file
  key never leaves the server; a coach sees only valid, expired or missing.
  """

  @template ~w(id kind title requirement status current_version_id current_version_number
               required_version_number archived_at inserted_at updated_at)a
  @version ~w(id template_id number title language change_kind content_hash published_by_id
              published_at)a
  @request ~w(id template_id user_id batch_id audience status requested_by_id requested_at
              signature_id closed_at)a
  @signature ~w(id template_id version_id version_number request_id user_id signed_at level
                provider content_hash typed_name ip_address user_agent evidence_hash
                evidence_sha256 evidence_byte_size)a
  @event ~w(id action actor_id subject_type subject_id subject_user_id details occurred_at)a
  @certificate ~w(id user_id issued_on expires_on content_type byte_size uploaded_by_id
                  inserted_at)a

  def template(template) do
    template
    |> Map.take(@template)
    |> maybe_versions(template)
  end

  defp maybe_versions(view, %{versions: versions}),
    do: Map.put(view, :versions, Enum.map(versions, &version/1))

  defp maybe_versions(view, _template), do: view

  def version(version) do
    view = Map.take(version, @version)
    if Map.has_key?(version, :body), do: Map.put(view, :body, version.body), else: view
  end

  def request(request), do: Map.take(request, @request)

  @doc "A signature for staff and for its signer: the evidence, never the drawn strokes' raw size."
  def signature(signature) do
    signature
    |> Map.take(@signature)
    |> Map.put(:has_drawn_signature, not is_nil(signature[:drawn_signature]))
    |> Map.put(:account, signature[:account])
  end

  def event(event), do: Map.take(event, @event)

  @doc "A member's item from `Documents.member_items/2`."
  def item(%{template: template} = item) do
    %{
      template_id: template.id,
      kind: template.kind,
      title: template.title,
      requirement: template.requirement,
      current_version_id: template.current_version_id,
      current_version_number: template.current_version_number,
      status: Atom.to_string(item.status),
      outstanding: item.outstanding,
      requested: item.requested,
      signature:
        item.signature &&
          Map.take(item.signature, [:id, :version_number, :signed_at, :content_hash])
    }
  end

  @doc "The full health certificate view (owner, staff with the capability)."
  def certificate(nil), do: nil
  def certificate(certificate), do: Map.take(certificate, @certificate)

  @doc "A coach's view: valid (also when expiring soon), expired or missing. No dates."
  def coach_status("expiring"), do: "valid"
  def coach_status(status), do: status
end
