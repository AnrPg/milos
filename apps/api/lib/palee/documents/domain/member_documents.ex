defmodule Palee.Documents.Domain.MemberDocuments do
  @moduledoc """
  What one client still has to do (ADR-252), and the booking gate.

  Every active, published document is listed with the client's status.
  Mandatory documents that are not signed (or need a new signature after a
  major version) are **outstanding**. Optional documents are only offered:
  never outstanding and never in the way of a booking. A pending request
  marks a document as asked for by staff.

  The booking gate refuses with `documents_required` when the box blocks
  bookings on unsigned mandatory documents and one is outstanding, or when
  it blocks bookings on health certificates and the client's is missing or
  expired.
  """

  alias Palee.Documents.Domain.{HealthCertificatePolicy, SignaturePolicy}

  @doc """
  One item per active, published template: `%{template, status, mandatory,
  outstanding, requested, signature}`, outstanding first.
  """
  def items(templates, signatures_by_template, requested_template_ids) do
    requested = MapSet.new(requested_template_ids)

    templates
    |> Enum.filter(&(&1.status == "active" and &1.current_version_number > 0))
    |> Enum.map(fn template ->
      signature = Map.get(signatures_by_template, template.id)
      status = SignaturePolicy.status(template, signature)
      mandatory = template.requirement == "mandatory"

      %{
        template: template,
        status: status,
        mandatory: mandatory,
        outstanding: mandatory and status != :signed,
        requested: MapSet.member?(requested, template.id),
        signature: signature
      }
    end)
    |> Enum.sort_by(&{not &1.outstanding, &1.status == :signed, &1.template.title})
  end

  @doc "The outstanding items of `items/3`."
  def outstanding(items), do: Enum.filter(items, & &1.outstanding)

  @doc """
  The health certificate as an outstanding item: its status when the box
  requires one and it is missing or expired, else nil.
  """
  def health_outstanding(%{health_certificate_required: true}, status)
      when status in ["missing", "expired"],
      do: status

  def health_outstanding(_settings, _status), do: nil

  @doc """
  `:ok` or `{:error, :documents_required, %{documents, health_certificate}}`
  where `documents` lists the blocking documents and `health_certificate`
  is `"missing"`, `"expired"` or nil.
  """
  def booking_gate(settings, items, health_status) do
    documents =
      if settings.block_booking_on_unsigned,
        do: items |> outstanding() |> Enum.map(&blocking_document/1),
        else: []

    health =
      if settings.block_booking_on_health_certificate and
           not HealthCertificatePolicy.usable?(health_status),
         do: health_status

    if documents == [] and is_nil(health),
      do: :ok,
      else: {:error, :documents_required, %{documents: documents, health_certificate: health}}
  end

  defp blocking_document(%{template: template, status: status}) do
    %{
      template_id: template.id,
      title: template.title,
      kind: template.kind,
      reason: Atom.to_string(status)
    }
  end
end
