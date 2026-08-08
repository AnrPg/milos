defmodule MilosTraining.Finance.Domain.InvoiceDocumentPolicy do
  @moduledoc false

  @max_bytes 10 * 1_024 * 1_024
  @allowed_types %{
    ".pdf" => "application/pdf",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp"
  }

  def max_bytes, do: @max_bytes
  def allowed_content_types, do: @allowed_types |> Map.values() |> Enum.uniq()

  def validate_request(file_name, content_type) do
    normalized_name = normalize_file_name(file_name)
    normalized_type = normalize_content_type(content_type)
    extension = normalized_name |> Path.extname() |> String.downcase()

    cond do
      normalized_name == "" or extension == "" ->
        {:error, :invalid_invoice_upload}

      String.length(normalized_name) > 180 ->
        {:error, :invalid_invoice_upload}

      String.contains?(normalized_name, ["/", "\\", <<0>>]) ->
        {:error, :invalid_invoice_upload}

      Map.get(@allowed_types, extension) != normalized_type ->
        {:error, :unsupported_invoice_upload_type}

      true ->
        {:ok,
         %{
           file_name: normalized_name,
           extension: extension,
           content_type: normalized_type,
           max_bytes: @max_bytes
         }}
    end
  end

  def storage_policy(%{content_type: content_type, max_bytes: max_bytes}) do
    %{content_type: content_type, max_bytes: max_bytes}
  end

  defp normalize_file_name(file_name) when is_binary(file_name), do: String.trim(file_name)
  defp normalize_file_name(_file_name), do: ""

  defp normalize_content_type(content_type) when is_binary(content_type) do
    content_type
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_content_type(_content_type), do: ""
end
