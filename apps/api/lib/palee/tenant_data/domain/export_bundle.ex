defmodule Palee.TenantData.Domain.ExportBundle do
  @moduledoc """
  Builds the tenant export and retention archive bundles (ADR-117): in-memory
  ZIP files of pretty-printed JSON documents, one per bounded context, plus a
  manifest. Pure apart from OTP's in-memory `:zip`; callers pass timestamps.
  """

  @format "palee-tenant-export/v1"
  @retention_format "palee-tenant-retention-archive/v1"

  def format, do: @format

  @doc """
  Full export: one JSON file per context, the account records, the stored
  objects manifest and the retention review.
  """
  def full_export(%{
        purge_id: purge_id,
        organization: organization,
        generated_at: generated_at,
        sections: sections,
        accounts: accounts,
        objects: objects,
        retention_review: retention_review
      }) do
    context_files =
      Enum.map(sections, fn %{policy: policy, tables: tables} ->
        {"contexts/#{policy.context}.json",
         %{
           "context" => policy.context,
           "disposition" => Atom.to_string(policy.disposition),
           "retain_years" => policy.retain_years,
           "basis" => policy.basis,
           "tables" => tables
         }}
      end)

    documents =
      context_files ++
        [
          {"identity/accounts.json", %{"accounts" => accounts}},
          {"storage/objects-manifest.json",
           %{
             "documents" => Enum.map(objects.documents, &object_entry/1),
             "avatars" => Enum.map(objects.avatars, &object_entry/1)
           }},
          {"retention-review.json", %{"contexts" => retention_review}}
        ]

    manifest = %{
      "format" => @format,
      "purge_id" => purge_id,
      "organization" => organization,
      "generated_at" => DateTime.to_iso8601(generated_at),
      "files" =>
        Enum.map(documents, fn {name, _doc} -> name end)
        |> then(&["manifest.json" | &1]),
      "contexts" =>
        Enum.map(sections, fn %{policy: policy, tables: tables} ->
          %{
            "context" => policy.context,
            "file" => "contexts/#{policy.context}.json",
            "record_count" => tables |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
          }
        end)
    }

    zip([{"manifest.json", manifest} | documents])
  end

  @doc """
  Retention archive: only rows that a context policy retains (anonymized where
  the policy says so), with their retention deadlines.
  """
  def retention_archive(%{
        purge_id: purge_id,
        organization: organization,
        generated_at: generated_at,
        sections: sections,
        retention_review: retention_review,
        retained_object_prefixes: retained_object_prefixes
      }) do
    retained_until =
      Map.new(retention_review, fn entry -> {entry["context"], entry["retained_until"]} end)

    documents =
      Enum.map(sections, fn %{policy: policy, tables: tables} ->
        {"contexts/#{policy.context}.json",
         %{
           "context" => policy.context,
           "disposition" => Atom.to_string(policy.disposition),
           "retained_until" => retained_until[policy.context],
           "basis" => policy.basis,
           "tables" => tables
         }}
      end)

    manifest = %{
      "format" => @retention_format,
      "purge_id" => purge_id,
      "organization" => Map.take(organization, ["id", "slug"]),
      "generated_at" => DateTime.to_iso8601(generated_at),
      "retained_object_prefixes" => retained_object_prefixes,
      "contexts" =>
        Enum.map(sections, fn %{policy: policy} ->
          %{
            "context" => policy.context,
            "disposition" => Atom.to_string(policy.disposition),
            "retained_until" => retained_until[policy.context]
          }
        end)
    }

    zip([{"retention-manifest.json", manifest} | documents])
  end

  @doc "Lower-case hex SHA-256 of a bundle, recorded for integrity checks."
  def sha256(binary) when is_binary(binary),
    do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp object_entry(%{key: key, size: size}), do: %{"key" => key, "size" => size}

  defp zip(documents) do
    files =
      Enum.map(documents, fn {name, document} ->
        {String.to_charlist(name),
         Jason.encode_to_iodata!(document, pretty: true) |> IO.iodata_to_binary()}
      end)

    case :zip.create(~c"tenant-export.zip", files, [:memory]) do
      {:ok, {_name, binary}} -> {:ok, binary}
      {:error, reason} -> {:error, {:export_bundle_failed, reason}}
    end
  end
end
