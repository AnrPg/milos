defmodule Palee.Documents.Ports.SignatureEvidenceStore do
  @moduledoc """
  Where signature evidence lives (ADR-252, V3 plan §3.2).

  The first adapter seals nothing and stores the PDF certificate through
  the existing tenant object storage (`documents/evidence/<id>.pdf` under
  the tenant prefix): a **simple** electronic signature (eIDAS art. 3(10))
  whose proof is its audit trail. An advanced or qualified signature
  provider plugs in here: `seal/3` hands the PDF and the evidence to the
  provider and returns what it signed, and `level/0`/`provider/0` are
  recorded on every signature.
  """

  @type context :: map()
  @type stored :: %{key: String.t(), sha256: String.t(), byte_size: pos_integer()}

  @doc "`\"simple\"`, `\"advanced\"` or `\"qualified\"` (eIDAS)."
  @callback level() :: String.t()

  @doc "Who produced the signature (`\"palee\"` for the simple signature)."
  @callback provider() :: String.t()

  @doc "Seals the certificate PDF (a provider's signature) or returns it unchanged."
  @callback seal(context(), pdf :: binary(), evidence :: map()) ::
              {:ok, binary()} | {:error, term()}

  @doc "Stores the (sealed) certificate of `signature_id`."
  @callback store(context(), signature_id :: String.t(), pdf :: binary()) ::
              {:ok, stored()} | {:error, term()}

  @doc "A short-lived download URL of a stored certificate."
  @callback download_url(context(), key :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
