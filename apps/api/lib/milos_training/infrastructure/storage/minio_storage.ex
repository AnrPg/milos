defmodule MilosTraining.Infrastructure.Storage.MinioStorage do
  @moduledoc false
  @behaviour MilosTraining.Application.Ports.DocumentStorage
  @behaviour MilosTraining.Application.Ports.AvatarStorage

  @expires_seconds 900
  @max_avatar_bytes 5 * 1_024 * 1_024
  @allowed_avatar_types ~w(image/jpeg image/png image/webp)

  def ensure_buckets do
    {document_config, _document_url, document_bucket} = ex_aws_config()
    {avatar_config, _avatar_url, avatar_bucket} = avatar_ex_aws_config()

    with :ok <- ensure_bucket(document_config, document_bucket),
         :ok <- ensure_bucket(avatar_config, avatar_bucket),
         :ok <- ensure_avatar_read_policy(avatar_config, avatar_bucket) do
      :ok
    end
  end

  def health_status do
    {config, _url_config, bucket} = ex_aws_config()

    case bucket_probe_operation(bucket) |> ExAws.request(config) do
      {:ok, _response} -> :ok
      _other -> :error
    end
  end

  @impl MilosTraining.Application.Ports.DocumentStorage
  def presigned_upload_url(key) do
    {storage_config, url_config, bucket} = ex_aws_config()

    with :ok <- ensure_bucket(storage_config, bucket) do
      ExAws.S3.presigned_url(url_config, :put, bucket, key,
        expires_in: @expires_seconds,
        virtual_host: false
      )
    end
  end

  @impl MilosTraining.Application.Ports.DocumentStorage
  def presigned_download_url(key) do
    {_storage_config, url_config, bucket} = ex_aws_config()

    ExAws.S3.presigned_url(url_config, :get, bucket, key,
      expires_in: @expires_seconds,
      virtual_host: false
    )
  end

  @impl true
  def create_upload(user_id, content_type, _byte_size) do
    extension = extension_for(content_type)
    key = "avatars/#{user_id}/#{Ecto.UUID.generate()}.#{extension}"
    {storage_config, url_config, bucket} = avatar_ex_aws_config()

    with :ok <- ensure_bucket(storage_config, bucket),
         :ok <- ensure_avatar_read_policy(storage_config, bucket),
         {:ok, url} <-
           ExAws.S3.presigned_url(url_config, :put, bucket, key,
             expires_in: @expires_seconds,
             virtual_host: false,
             headers: avatar_upload_headers(content_type)
           ) do
      {:ok,
       %{
         upload_url: url,
         key: key,
         required_headers: Map.new(avatar_upload_headers(content_type)),
         expires_in: @expires_seconds,
         max_bytes: @max_avatar_bytes
       }}
    end
  end

  @impl true
  def validate_uploaded(user_id, "avatars/" <> _rest = key) do
    expected_prefix = "avatars/#{user_id}/"

    if String.starts_with?(key, expected_prefix) do
      {storage_config, _url_config, bucket} = avatar_ex_aws_config()

      with {:ok, %{headers: headers}} <-
             avatar_probe_operation(bucket, key) |> ExAws.request(storage_config),
           {:ok, content_type, byte_size} <- avatar_metadata(headers),
           true <- content_type in @allowed_avatar_types and byte_size <= @max_avatar_bytes do
        {:ok, avatar_public_url(bucket, key)}
      else
        _ -> {:error, :invalid_avatar_upload}
      end
    else
      {:error, :invalid_avatar_upload}
    end
  end

  def validate_uploaded(_user_id, _key), do: {:error, :invalid_avatar_upload}

  @doc false
  def bucket_probe_operation(bucket), do: ExAws.S3.get_bucket_location(bucket)

  @doc false
  def avatar_upload_headers(content_type), do: [{"content-type", content_type}]

  @doc false
  def avatar_probe_operation(bucket, key) do
    ExAws.S3.get_object(bucket, key, range: "bytes=0-0")
  end

  defp ex_aws_config do
    endpoint = Application.get_env(:milos_training, :minio_endpoint, "http://localhost:9000")
    public_endpoint = public_endpoint(endpoint)
    access_key = Application.get_env(:milos_training, :minio_access_key, "minioadmin")
    secret_key = Application.get_env(:milos_training, :minio_secret_key, "minioadmin")
    bucket = Application.get_env(:milos_training, :minio_bucket, "milos-invoices")

    {build_ex_aws_config(endpoint, access_key, secret_key),
     build_ex_aws_config(public_endpoint, access_key, secret_key), bucket}
  end

  defp avatar_ex_aws_config do
    endpoint = Application.get_env(:milos_training, :minio_endpoint, "http://localhost:9000")
    public_endpoint = public_endpoint(endpoint)
    access_key = Application.get_env(:milos_training, :minio_access_key, "minioadmin")
    secret_key = Application.get_env(:milos_training, :minio_secret_key, "minioadmin")
    bucket = Application.get_env(:milos_training, :minio_avatar_bucket, "milos-avatars")

    {build_ex_aws_config(endpoint, access_key, secret_key),
     build_ex_aws_config(public_endpoint, access_key, secret_key), bucket}
  end

  defp ensure_bucket(config, bucket) do
    case bucket_probe_operation(bucket) |> ExAws.request(config) do
      {:ok, _response} ->
        :ok

      {:error, {:http_error, 404, _response}} ->
        create_bucket(config, bucket)

      {:error, {:http_error, 403, _response}} ->
        create_bucket(config, bucket)

      error ->
        error
    end
  end

  defp create_bucket(config, bucket) do
    case ExAws.S3.put_bucket(bucket, "us-east-1") |> ExAws.request(config) do
      {:ok, _response} -> :ok
      {:error, {:http_error, 409, _response}} -> :ok
      error -> error
    end
  end

  defp ensure_avatar_read_policy(config, bucket) do
    policy =
      Jason.encode!(%{
        Version: "2012-10-17",
        Statement: [
          %{
            Effect: "Allow",
            Principal: "*",
            Action: ["s3:GetObject"],
            Resource: ["arn:aws:s3:::#{bucket}/avatars/*"]
          }
        ]
      })

    case ExAws.S3.put_bucket_policy(bucket, policy) |> ExAws.request(config) do
      {:ok, _response} -> :ok
      error -> error
    end
  end

  defp build_ex_aws_config(endpoint, access_key, secret_key) do
    uri = URI.parse(endpoint)

    ExAws.Config.new(:s3,
      access_key_id: access_key,
      secret_access_key: secret_key,
      scheme: "#{uri.scheme}://",
      host: uri.host,
      port: uri.port,
      region: "us-east-1"
    )
  end

  defp avatar_public_url(bucket, key) do
    endpoint = Application.get_env(:milos_training, :minio_endpoint, "http://localhost:9000")

    "#{String.trim_trailing(public_endpoint(endpoint), "/")}/#{bucket}/#{key}"
  end

  defp public_endpoint(endpoint) do
    Application.get_env(:milos_training, :minio_public_endpoint) || endpoint
  end

  defp extension_for("image/jpeg"), do: "jpg"
  defp extension_for("image/png"), do: "png"
  defp extension_for("image/webp"), do: "webp"

  defp avatar_metadata(headers) do
    normalized = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)
    content_type = normalized["content-type"]
    byte_size = total_object_size(normalized)

    case byte_size do
      byte_size when is_integer(byte_size) and byte_size > 0 -> {:ok, content_type, byte_size}
      _ -> {:error, :invalid_avatar_upload}
    end
  end

  defp total_object_size(%{"content-range" => content_range}) do
    case Regex.run(~r{/([0-9]+)$}, to_string(content_range), capture: :all_but_first) do
      [value] -> String.to_integer(value)
      _ -> nil
    end
  end

  defp total_object_size(headers) do
    case Integer.parse(to_string(headers["content-length"])) do
      {byte_size, ""} -> byte_size
      _ -> nil
    end
  end
end
