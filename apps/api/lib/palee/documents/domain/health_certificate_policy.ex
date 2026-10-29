defmodule Palee.Documents.Domain.HealthCertificatePolicy do
  @moduledoc """
  Health certificates (Βεβαίωση υγείας, ADR-252).

  In Greece a private gym asks for a certificate from a GP or cardiologist
  (a paediatrician under 16), valid for one year. Palee keeps only what the
  box needs to check that: the issue date, the expiry date and the file
  (GDPR art. 9: health data, minimised). The file is a PDF or an image of
  at most 10 MB.

  `expires_on` is the first day the certificate is no longer valid; by
  default the issue date plus the box's validity (12 months). A certificate
  is `valid` before it, `expiring` within the reminder window, and
  `expired` from it on; a person without one is `missing`.
  """

  @content_types %{
    "application/pdf" => ".pdf",
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp"
  }
  @max_bytes 10 * 1024 * 1024
  @max_validity_months 24

  def content_types, do: Map.keys(@content_types)
  def max_bytes, do: @max_bytes

  @doc "`{:ok, %{content_type, extension, max_bytes}}` for an upload of this type."
  def validate_upload(content_type) do
    case Map.fetch(@content_types, content_type) do
      {:ok, extension} ->
        {:ok, %{content_type: content_type, extension: extension, max_bytes: @max_bytes}}

      :error ->
        {:error, {:invalid_fields, %{content_type: "unsupported"}}}
    end
  end

  @doc """
  Checks the uploaded file's leading bytes and size against its type:
  `:ok` or `{:error, :health_certificate_file_invalid}`.
  """
  def validate_file(content_type, head, byte_size) do
    cond do
      not is_integer(byte_size) or byte_size <= 0 or byte_size > @max_bytes ->
        {:error, :health_certificate_file_invalid}

      magic?(content_type, head) ->
        :ok

      true ->
        {:error, :health_certificate_file_invalid}
    end
  end

  defp magic?("application/pdf", "%PDF-" <> _), do: true
  defp magic?("image/jpeg", <<0xFF, 0xD8, 0xFF, _::binary>>), do: true
  defp magic?("image/png", <<0x89, "PNG", _::binary>>), do: true
  defp magic?("image/webp", <<"RIFF", _size::binary-size(4), "WEBP", _::binary>>), do: true
  defp magic?(_type, _head), do: false

  @doc """
  The certificate's dates: `{:ok, %{issued_on, expires_on}}` or field
  errors. The issue date cannot be in the future; the expiry (default:
  issue date + `validity_months`) must be after the issue date, at most
  24 months later, and not already past.
  """
  def validate_dates(issued_on, expires_on, %Date{} = today, validity_months) do
    with {:ok, issued} <- date(issued_on, :issued_on, required: true),
         {:ok, expires} <- date(expires_on, :expires_on, required: false) do
      expires = expires || Date.shift(issued, month: validity_months)
      latest = Date.shift(issued, month: @max_validity_months)

      cond do
        Date.compare(issued, today) == :gt ->
          {:error, {:invalid_fields, %{issued_on: "in_future"}}}

        Date.compare(expires, issued) != :gt ->
          {:error, {:invalid_fields, %{expires_on: "before_issue"}}}

        Date.compare(expires, latest) == :gt ->
          {:error, {:invalid_fields, %{expires_on: "too_late"}}}

        Date.compare(expires, today) != :gt ->
          {:error, {:invalid_fields, %{expires_on: "already_expired"}}}

        true ->
          {:ok, %{issued_on: issued, expires_on: expires}}
      end
    end
  end

  defp date(%Date{} = date, _field, _opts), do: {:ok, date}

  defp date(value, field, opts) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> date(nil, field, Keyword.put(opts, :invalid, true))
    end
  end

  defp date(_value, field, opts) do
    cond do
      opts[:invalid] -> {:error, {:invalid_fields, %{field => "invalid"}}}
      opts[:required] -> {:error, {:invalid_fields, %{field => "required"}}}
      true -> {:ok, nil}
    end
  end

  @doc "`\"missing\"`, `\"valid\"`, `\"expiring\"` or `\"expired\"` on `today`."
  def status(nil, _today, _reminder_days), do: "missing"

  def status(%{expires_on: expires_on}, %Date{} = today, reminder_days) do
    cond do
      Date.compare(today, expires_on) != :lt -> "expired"
      Date.diff(expires_on, today) <= reminder_days -> "expiring"
      true -> "valid"
    end
  end

  @doc "Whether the certificate still counts (valid or expiring)."
  def usable?(status), do: status in ["valid", "expiring"]

  @doc """
  Whether the holder should hear about the expiry today: inside the
  reminder window, not expired, and not yet reminded for this expiry date.
  """
  def reminder_due?(%{expires_on: expires_on, reminded_for: reminded_for}, today, days) do
    status(%{expires_on: expires_on}, today, days) == "expiring" and reminded_for != expires_on
  end

  @doc "Storage path of an uploaded file, relative to the tenant prefix."
  def relative_key(user_id, extension),
    do: "health-certificates/#{user_id}/#{Ecto.UUID.generate()}#{extension}"

  @doc "Whether `key` is an upload of `user_id`'s under the tenant prefix."
  def key_of?(key, prefix, user_id) when is_binary(key),
    do: String.starts_with?(key, prefix <> "health-certificates/#{user_id}/")

  def key_of?(_key, _prefix, _user_id), do: false
end
