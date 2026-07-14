defmodule MilosTraining.Infrastructure.Storage.MinioStorage do
  @moduledoc false

  @expires_seconds 900

  def presigned_upload_url(key) do
    {storage_config, url_config, bucket} = ex_aws_config()

    with :ok <- ensure_bucket(storage_config, bucket) do
      ExAws.S3.presigned_url(url_config, :put, bucket, key,
        expires_in: @expires_seconds,
        virtual_host: false
      )
    end
  end

  def presigned_download_url(key) do
    {_storage_config, url_config, bucket} = ex_aws_config()

    ExAws.S3.presigned_url(url_config, :get, bucket, key,
      expires_in: @expires_seconds,
      virtual_host: false
    )
  end

  def presigned_avatar_upload_url(user_id) do
    key = "avatars/#{user_id}"
    {storage_config, url_config, bucket} = avatar_ex_aws_config()

    with :ok <- ensure_bucket(storage_config, bucket),
         :ok <- ensure_avatar_read_policy(storage_config, bucket),
         {:ok, url} <-
           ExAws.S3.presigned_url(url_config, :put, bucket, key,
             expires_in: @expires_seconds,
             virtual_host: false
           ) do
      {:ok, %{upload_url: url, public_url: avatar_public_url(bucket, key), key: key}}
    end
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
    case ExAws.S3.head_bucket(bucket) |> ExAws.request(config) do
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
end
