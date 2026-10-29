defmodule Palee.Documents.Ports.CertificateRenderer do
  @moduledoc """
  Renders the signature certificate (ADR-252): the signed text and the
  evidence of the signature, as a PDF the box and the member can keep.

  `certificate` holds `business_name`, `title`, `language`, `body`,
  `version_number`, `local_signed_at` (the gym-local time, text) and the
  `evidence` map with its `evidence_hash`.
  """

  @callback render(certificate :: map()) :: {:ok, binary()} | {:error, term()}
end
