defmodule Palee.Infrastructure.Storage.MinioStorage do
  @moduledoc false
  @behaviour Palee.Application.Ports.DocumentStorage
  @behaviour Palee.Application.Ports.AvatarStorage
  @behaviour Palee.Application.Ports.TenantObjectStore
  require Logger

  @expires_seconds 900
  @max_avatar_bytes 5 * 1_024 * 1_024
  @allowed_avatar_types ~w(image/jpeg image/png image/webp image/gif image/bmp image/avif)
  @delete_batch_size 1_000

  # --- ADR-117 tenant object inventory/cleanup -------------------------------

  @impl Palee.Application.Ports.TenantObjectStore
  def put_object(bucket, key, body, content_type) when is_binary(key) and is_binary(body) do
    {config, _url_config, bucket_name} = bucket_config(bucket)

    with :ok <- ensure_bucket(config, bucket_name) do
      case ExAws.S3.put_object(bucket_name, key, body, content_type: content_type)
           |> ExAws.request(config) do
        {:ok, _response} -> :ok
        {:error, reason} -> {:error, {:object_store_failed, reason}}
      end
    end
  end

  @impl Palee.Application.Ports.TenantObjectStore
  def list_objects(bucket, prefix) when is_binary(prefix) and prefix != "" do
    {config, _url_config, bucket_name} = bucket_config(bucket)
    list_objects_page(config, bucket_name, prefix, nil, [])
  end

  @impl Palee.Application.Ports.TenantObjectStore
  def delete_objects(_bucket, []), do: {:ok, 0}

  def delete_objects(bucket, keys) when is_list(keys) do
    {config, _url_config, bucket_name} = bucket_config(bucket)

    keys
    |> Enum.chunk_every(@delete_batch_size)
    |> Enum.reduce_while({:ok, 0}, fn batch, {:ok, deleted} ->
      case ExAws.S3.delete_multiple_objects(bucket_name, batch, quiet: true)
           |> Map.put(:parser, & &1)
           |> ExAws.request(config) do
        {:ok, %{body: body}} when is_binary(body) ->
          if String.contains?(body, "<Error>"),
            do: {:halt, {:error, {:object_store_failed, :partial_delete}}},
            else: {:cont, {:ok, deleted + length(batch)}}

        {:ok, _response} ->
          {:cont, {:ok, deleted + length(batch)}}

        {:error, reason} ->
          {:halt, {:error, {:object_store_failed, reason}}}
      end
    end)
  end

  @impl Palee.Application.Ports.TenantObjectStore
  def presigned_object_url(bucket, key) when is_binary(key) do
    {_config, url_config, bucket_name} = bucket_config(bucket)

    ExAws.S3.presigned_url(url_config, :get, bucket_name, key,
      expires_in: @expires_seconds,
      virtual_host: false
    )
  end

  # ADR-121: tenant logos share the public media (avatar) bucket; the bucket
  # policy makes only `organizations/*/branding/logo/*` publicly readable.
  @impl Palee.Application.Ports.TenantObjectStore
  def presigned_upload(bucket, key, content_type) when is_binary(key) do
    {storage_config, url_config, bucket_name} = bucket_config(bucket)
    headers = [{"content-type", content_type}]

    with :ok <- ensure_bucket(storage_config, bucket_name),
         :ok <- ensure_public_read_policy(bucket, storage_config, bucket_name),
         {:ok, url} <-
           ExAws.S3.presigned_url(url_config, :put, bucket_name, key,
             expires_in: @expires_seconds,
             virtual_host: false,
             headers: headers
           ) do
      {:ok, %{url: url, headers: Map.new(headers)}}
    else
      {:error, reason} -> {:error, {:object_store_failed, reason}}
    end
  end

  @impl Palee.Application.Ports.TenantObjectStore
  def probe_object(bucket, key, bytes) when is_binary(key) and is_integer(bytes) and bytes > 0 do
    {storage_config, _url_config, bucket_name} = bucket_config(bucket)

    case ExAws.S3.get_object(bucket_name, key, range: "bytes=0-#{bytes - 1}")
         |> ExAws.request(storage_config) do
      {:ok, %{headers: headers, body: body}} ->
        normalized = Map.new(headers, fn {name, value} -> {String.downcase(name), value} end)
        {:ok, %{head: to_string(body), byte_size: total_object_size(normalized)}}

      {:error, {:http_error, 404, _response}} ->
        {:error, :not_found}

      # An empty object cannot satisfy any byte range.
      {:error, {:http_error, 416, _response}} ->
        {:ok, %{head: "", byte_size: 0}}

      {:error, reason} ->
        {:error, {:object_store_failed, reason}}
    end
  end

  # ADR-157: post media are processed from a local copy of the upload.
  @impl Palee.Application.Ports.TenantObjectStore
  def download_object(bucket, key, path) when is_binary(key) and is_binary(path) do
    {storage_config, _url_config, bucket_name} = bucket_config(bucket)

    case ExAws.S3.download_file(bucket_name, key, path) |> ExAws.request(storage_config) do
      {:ok, _done} -> :ok
      {:error, {:http_error, 404, _response}} -> {:error, :not_found}
      {:error, reason} -> {:error, {:object_store_failed, reason}}
    end
  end

  @impl Palee.Application.Ports.TenantObjectStore
  def public_object_url(bucket, key)
      when bucket in [:branding, :media_public] and is_binary(key) do
    {_storage_config, _url_config, bucket_name} = bucket_config(bucket)
    {:ok, avatar_public_url(bucket_name, key)}
  end

  def public_object_url(_bucket, _key), do: {:error, :not_public}

  defp ensure_public_read_policy(bucket, config, bucket_name)
       when bucket in [:branding, :media_public],
       do: ensure_avatar_read_policy(config, bucket_name)

  defp ensure_public_read_policy(_bucket, _config, _bucket_name), do: :ok

  defp bucket_config(:documents), do: ex_aws_config()
  defp bucket_config(:avatars), do: avatar_ex_aws_config()
  defp bucket_config(:branding), do: avatar_ex_aws_config()
  # ADR-148: public box photos share the public media bucket; post and body
  # photos live in a private bucket read only through presigned URLs.
  defp bucket_config(:media_public), do: avatar_ex_aws_config()
  defp bucket_config(:media_private), do: media_ex_aws_config()

  defp list_objects_page(config, bucket_name, prefix, token, acc) do
    options =
      [prefix: prefix, max_keys: 1_000] ++
        if(token, do: [continuation_token: token], else: [])

    # The ExAws list parser needs SweetXml, which this app does not depend on;
    # the response is parsed by parse_list_objects_xml/1 instead.
    case ExAws.S3.list_objects_v2(bucket_name, options)
         |> Map.put(:parser, & &1)
         |> ExAws.request(config) do
      {:ok, %{body: body}} when is_binary(body) ->
        {objects, next_token} = parse_list_objects_xml(body)
        acc = acc ++ objects

        if next_token,
          do: list_objects_page(config, bucket_name, prefix, next_token, acc),
          else: {:ok, acc}

      {:error, {:http_error, 404, _response}} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, {:object_store_failed, reason}}
    end
  end

  @doc false
  def parse_list_objects_xml(body) when is_binary(body) do
    objects =
      ~r{<Contents>(.*?)</Contents>}s
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.flat_map(fn [contents] ->
        with [key] <- Regex.run(~r{<Key>(.*?)</Key>}s, contents, capture: :all_but_first) do
          size =
            case Regex.run(~r{<Size>(\d+)</Size>}, contents, capture: :all_but_first) do
              [size] -> String.to_integer(size)
              _missing -> 0
            end

          [%{key: unescape_xml(key), size: size}]
        else
          _missing -> []
        end
      end)

    truncated? = Regex.match?(~r{<IsTruncated>true</IsTruncated>}, body)

    next_token =
      case Regex.run(~r{<NextContinuationToken>(.*?)</NextContinuationToken>}s, body,
             capture: :all_but_first
           ) do
        [token] when truncated? -> unescape_xml(token)
        _other -> nil
      end

    {objects, next_token}
  end

  defp unescape_xml(value) do
    value
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end

  # ---------------------------------------------------------------------------

  def ensure_buckets do
    {document_config, _document_url, document_bucket} = ex_aws_config()
    {avatar_config, _avatar_url, avatar_bucket} = avatar_ex_aws_config()

    {media_config, _media_url, media_bucket} = media_ex_aws_config()

    with :ok <- ensure_bucket(document_config, document_bucket),
         :ok <- ensure_bucket(avatar_config, avatar_bucket),
         :ok <- ensure_bucket(media_config, media_bucket),
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

  @impl Palee.Application.Ports.DocumentStorage
  def presigned_upload_post(key, policy) do
    {storage_config, url_config, bucket} = ex_aws_config()
    content_type = Map.fetch!(policy, :content_type)
    max_bytes = Map.fetch!(policy, :max_bytes)

    with :ok <- ensure_bucket(storage_config, bucket) do
      upload =
        ExAws.S3.presigned_post(url_config, bucket, key,
          expires_in: @expires_seconds,
          virtual_host: false,
          content_length_range: [1, max_bytes],
          custom_conditions: [%{"Content-Type" => content_type}]
        )

      {:ok,
       %{
         url: upload.url,
         fields: Map.put(upload.fields, "Content-Type", content_type),
         required_headers: %{},
         expires_in: @expires_seconds,
         max_bytes: max_bytes,
         content_type: content_type,
         method: "POST"
       }}
    end
  end

  @impl Palee.Application.Ports.DocumentStorage
  def presigned_download_url(key) do
    {_storage_config, url_config, bucket} = ex_aws_config()

    ExAws.S3.presigned_url(url_config, :get, bucket, key,
      expires_in: @expires_seconds,
      virtual_host: false
    )
  end

  @impl Palee.Application.Ports.DocumentStorage
  def validate_uploaded_document(key, policy) do
    {storage_config, _url_config, bucket} = ex_aws_config()
    expected_content_type = Map.fetch!(policy, :content_type)
    max_bytes = Map.fetch!(policy, :max_bytes)

    case ExAws.S3.head_object(bucket, key) |> ExAws.request(storage_config) do
      {:ok, %{headers: headers}} ->
        with {:ok, content_type} <- normalized_header_value(headers, "content-type"),
             :ok <- validate_document_content_type(content_type, expected_content_type),
             {:ok, byte_size} <- document_byte_size(headers),
             :ok <- validate_document_size(byte_size, max_bytes) do
          {:ok, %{content_type: content_type, byte_size: byte_size}}
        end

      {:error, {:http_error, 404, _body}} ->
        {:error, :document_upload_missing}

      {:error, _reason} ->
        {:error, :document_upload_unverified}
    end
  end

  @impl true
  def create_upload(user_id, content_type, _byte_size) do
    extension = extension_for(content_type)
    key = "users/#{user_id}/avatars/#{Ecto.UUID.generate()}.#{extension}"
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
  def validate_uploaded(user_id, "users/" <> _rest = key) do
    expected_prefix = "users/#{user_id}/avatars/"

    if String.starts_with?(key, expected_prefix) do
      {storage_config, _url_config, bucket} = avatar_ex_aws_config()

      with {:ok, %{headers: headers, body: body}} <-
             request_avatar_probe(storage_config, bucket, key, avatar_public_url(bucket, key)),
           {:ok, _content_type, byte_size} <- avatar_metadata(headers, body),
           :ok <- validate_avatar_size(byte_size) do
        {:ok, avatar_public_url(bucket, key)}
      else
        error ->
          reason = avatar_validation_reason(error)

          Logger.warning(
            "avatar_upload_validation_failed reason=#{inspect(error)} bucket=#{bucket} key_prefix=#{expected_prefix}"
          )

          {:error, reason}
      end
    else
      {:error, :avatar_key_forbidden}
    end
  end

  def validate_uploaded(_user_id, _key), do: {:error, :invalid_avatar_upload}

  @doc false
  def bucket_probe_operation(bucket), do: ExAws.S3.get_bucket_location(bucket)

  @doc false
  def avatar_upload_headers(content_type), do: [{"content-type", content_type}]

  @doc false
  def avatar_probe_operation(bucket, key) do
    ExAws.S3.get_object(bucket, key, range: "bytes=0-15")
  end

  defp request_avatar_probe(config, bucket, key, public_url) do
    avatar_probe_operation(bucket, key)
    |> ExAws.request(config)
    |> avatar_probe_result(fn -> request_public_avatar_probe(public_url) end)
  end

  @doc false
  def avatar_probe_result({:ok, _response} = result, _public_probe), do: result

  def avatar_probe_result({:error, _reason}, public_probe) when is_function(public_probe, 0),
    do: public_probe.()

  defp request_public_avatar_probe(public_url) do
    case Req.get(public_url,
           headers: [{"range", "bytes=0-15"}],
           retry: false,
           receive_timeout: 5_000
         ) do
      {:ok, %{status: status, headers: headers, body: body}} when status in 200..299 ->
        {:ok, %{headers: headers, body: body}}

      {:ok, %{status: status} = response} ->
        {:error, {:http_error, status, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_avatar_size(byte_size)
       when is_integer(byte_size) and byte_size <= @max_avatar_bytes,
       do: :ok

  defp validate_avatar_size(byte_size), do: {:error, {:avatar_too_large, byte_size}}

  defp validate_document_content_type(content_type, expected_content_type) do
    if content_type == expected_content_type,
      do: :ok,
      else: {:error, :document_upload_content_type_mismatch}
  end

  defp document_byte_size(headers) do
    case header_value(headers, "content-length") do
      {:ok, value} ->
        case Integer.parse(value) do
          {byte_size, ""} when byte_size > 0 -> {:ok, byte_size}
          _other -> {:error, :document_upload_metadata_missing}
        end

      :error ->
        {:error, :document_upload_metadata_missing}
    end
  end

  defp validate_document_size(byte_size, max_bytes) when byte_size <= max_bytes, do: :ok

  defp validate_document_size(byte_size, _max_bytes),
    do: {:error, {:document_too_large, byte_size}}

  defp avatar_validation_reason({:error, {:http_error, 404, _response}}),
    do: :avatar_upload_missing

  defp avatar_validation_reason({:error, {:http_error, 403, _response}}),
    do: :avatar_upload_unverified

  defp avatar_validation_reason({:error, :unsupported_avatar_type}), do: :unsupported_avatar_type

  defp avatar_validation_reason({:error, :avatar_upload_metadata_missing}),
    do: :avatar_upload_metadata_missing

  defp avatar_validation_reason({:error, {:avatar_too_large, byte_size}}),
    do: {:avatar_too_large, byte_size}

  defp avatar_validation_reason({:error, _reason}), do: :avatar_storage_unavailable
  defp avatar_validation_reason(_error), do: :avatar_storage_unavailable

  defp ex_aws_config do
    endpoint = Application.get_env(:palee, :minio_endpoint, "http://localhost:9000")
    public_endpoint = public_endpoint(endpoint)
    access_key = Application.get_env(:palee, :minio_access_key, "minioadmin")
    secret_key = Application.get_env(:palee, :minio_secret_key, "minioadmin")
    bucket = Application.get_env(:palee, :minio_bucket, "milos-invoices")

    {build_ex_aws_overrides(endpoint, access_key, secret_key),
     build_ex_aws_config(public_endpoint, access_key, secret_key), bucket}
  end

  defp avatar_ex_aws_config do
    endpoint = Application.get_env(:palee, :minio_endpoint, "http://localhost:9000")
    public_endpoint = public_endpoint(endpoint)
    access_key = Application.get_env(:palee, :minio_access_key, "minioadmin")
    secret_key = Application.get_env(:palee, :minio_secret_key, "minioadmin")
    bucket = Application.get_env(:palee, :minio_avatar_bucket, "milos-avatars")

    {build_ex_aws_overrides(endpoint, access_key, secret_key),
     build_ex_aws_config(public_endpoint, access_key, secret_key), bucket}
  end

  defp media_ex_aws_config do
    endpoint = Application.get_env(:palee, :minio_endpoint, "http://localhost:9000")
    public_endpoint = public_endpoint(endpoint)
    access_key = Application.get_env(:palee, :minio_access_key, "minioadmin")
    secret_key = Application.get_env(:palee, :minio_secret_key, "minioadmin")
    bucket = Application.get_env(:palee, :minio_media_bucket, "milos-media")

    {build_ex_aws_overrides(endpoint, access_key, secret_key),
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

  @doc false
  # Anonymous reads are limited to avatars and (ADR-121) tenant logos; every
  # other key in the public media bucket stays private.
  def public_read_policy(bucket) do
    %{
      Version: "2012-10-17",
      Statement: [
        %{
          Effect: "Allow",
          Principal: "*",
          Action: ["s3:GetObject"],
          Resource: [
            "arn:aws:s3:::#{bucket}/users/*/avatars/*",
            "arn:aws:s3:::#{bucket}/organizations/*/branding/logo/*",
            "arn:aws:s3:::#{bucket}/organizations/*/media/public/*"
          ]
        }
      ]
    }
  end

  defp ensure_avatar_read_policy(config, bucket) do
    policy = Jason.encode!(public_read_policy(bucket))

    case ExAws.S3.put_bucket_policy(bucket, policy) |> ExAws.request(config) do
      {:ok, _response} -> :ok
      error -> error
    end
  end

  # Requests take keyword overrides (ExAws.request/2); presigning takes a
  # resolved config map (ExAws.S3.presigned_*), so the public URL config is
  # resolved eagerly while the storage config stays as overrides.
  defp build_ex_aws_overrides(endpoint, access_key, secret_key) do
    uri = URI.parse(endpoint)

    [
      access_key_id: access_key,
      secret_access_key: secret_key,
      scheme: "#{uri.scheme}://",
      host: uri.host,
      port: uri.port,
      region: "us-east-1"
    ]
  end

  defp build_ex_aws_config(endpoint, access_key, secret_key),
    do: ExAws.Config.new(:s3, build_ex_aws_overrides(endpoint, access_key, secret_key))

  defp avatar_public_url(bucket, key) do
    endpoint = Application.get_env(:palee, :minio_endpoint, "http://localhost:9000")

    "#{String.trim_trailing(public_endpoint(endpoint), "/")}/#{bucket}/#{key}"
  end

  defp public_endpoint(endpoint) do
    Application.get_env(:palee, :minio_public_endpoint) || endpoint
  end

  defp extension_for("image/jpeg"), do: "jpg"
  defp extension_for("image/png"), do: "png"
  defp extension_for("image/webp"), do: "webp"
  defp extension_for("image/gif"), do: "gif"
  defp extension_for("image/bmp"), do: "bmp"
  defp extension_for("image/avif"), do: "avif"

  @doc false
  def avatar_metadata(headers, body) do
    normalized = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)
    content_type = normalized["content-type"] |> normalize_content_type()
    detected_type = image_type_from_probe(body)
    byte_size = total_object_size(normalized)

    cond do
      detected_type not in @allowed_avatar_types ->
        {:error, :unsupported_avatar_type}

      content_type in @allowed_avatar_types and is_integer(byte_size) and byte_size > 0 ->
        {:ok, content_type, byte_size}

      is_integer(byte_size) and byte_size > 0 ->
        {:ok, detected_type, byte_size}

      true ->
        {:error, :avatar_upload_metadata_missing}
    end
  end

  defp normalized_header_value(headers, header) do
    with {:ok, value} <- header_value(headers, header) do
      {:ok, normalize_content_type(value)}
    end
  end

  defp header_value(headers, header) do
    normalized =
      Map.new(headers, fn {key, value} ->
        {String.downcase(to_string(key)), to_string(value)}
      end)

    case normalized[String.downcase(header)] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> :error
    end
  end

  defp normalize_content_type(nil), do: nil

  defp normalize_content_type(content_type) do
    content_type
    |> to_string()
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp image_type_from_probe(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"

  defp image_type_from_probe(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>),
    do: "image/png"

  defp image_type_from_probe(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: "image/webp"

  defp image_type_from_probe(<<"GIF8", _version::binary-size(2), _rest::binary>>), do: "image/gif"
  defp image_type_from_probe(<<"BM", _rest::binary>>), do: "image/bmp"

  defp image_type_from_probe(
         <<_size::binary-size(4), "ftyp", brand::binary-size(4), _rest::binary>>
       )
       when brand in ["avif", "avis"],
       do: "image/avif"

  defp image_type_from_probe(_body), do: nil

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
