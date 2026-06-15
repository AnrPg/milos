defmodule MilosTraining.Infrastructure.Storage.MinioStorage do
  @moduledoc false

  @expires_seconds 900

  def presigned_upload_url(key) do
    {config, bucket} = ex_aws_config()
    ExAws.S3.presigned_url(config, :put, bucket, key,
      expires_in: @expires_seconds,
      virtual_host: false
    )
  end

  def presigned_download_url(key) do
    {config, bucket} = ex_aws_config()
    ExAws.S3.presigned_url(config, :get, bucket, key,
      expires_in: @expires_seconds,
      virtual_host: false
    )
  end

  defp ex_aws_config do
    endpoint = Application.get_env(:milos_training, :minio_endpoint, "http://localhost:9000")
    access_key = Application.get_env(:milos_training, :minio_access_key, "minioadmin")
    secret_key = Application.get_env(:milos_training, :minio_secret_key, "minioadmin")
    bucket = Application.get_env(:milos_training, :minio_bucket, "milos-invoices")

    uri = URI.parse(endpoint)

    config =
      ExAws.Config.new(:s3,
        access_key_id: access_key,
        secret_access_key: secret_key,
        scheme: "#{uri.scheme}://",
        host: uri.host,
        port: uri.port,
        region: "us-east-1"
      )

    {config, bucket}
  end
end
