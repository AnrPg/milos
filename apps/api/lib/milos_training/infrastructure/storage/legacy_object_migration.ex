defmodule MilosTraining.Infrastructure.Storage.LegacyObjectMigration do
  @moduledoc """
  Operator-controlled migration for pre-tenancy object keys.

  The migration is dry-run by default. It copies legacy invoice and avatar objects
  into their canonical ownership prefixes, verifies the copied bytes, then updates
  the persisted database key or URL only after verification.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias MilosTraining.Application.OwnershipKeys
  alias MilosTraining.Finance.FinanceInvoice
  alias MilosTraining.Identity.User
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Repo

  defmodule Item do
    @moduledoc false
    defstruct [
      :kind,
      :record,
      :source_bucket,
      :source_key,
      :destination_bucket,
      :destination_key,
      :persisted_value
    ]
  end

  defmodule S3ObjectStore do
    @moduledoc false

    def get_object(config, bucket, key) do
      case ExAws.S3.get_object(bucket, key) |> ExAws.request(config) do
        {:ok, %{body: body} = response} when is_binary(body) ->
          {:ok, response}

        {:error, {:http_error, 404, _response}} ->
          {:error, :object_not_found}

        error ->
          error
      end
    end

    def put_object(config, bucket, key, body) when is_binary(body) do
      case ExAws.S3.put_object(bucket, key, body) |> ExAws.request(config) do
        {:ok, _response} -> :ok
        error -> error
      end
    end

    def delete_object(config, bucket, key) do
      case ExAws.S3.delete_object(bucket, key) |> ExAws.request(config) do
        {:ok, _response} -> :ok
        error -> error
      end
    end
  end

  def run(options \\ []) do
    apply? = Keyword.get(options, :apply, false)
    delete_legacy? = Keyword.get(options, :delete_legacy, false)
    object_store = Keyword.get(options, :object_store, S3ObjectStore)
    limit = Keyword.get(options, :limit)

    items = invoice_items(limit) ++ avatar_items(limit)

    results =
      Enum.map(items, fn item ->
        migrate_item(item,
          apply: apply?,
          delete_legacy: delete_legacy?,
          object_store: object_store,
          document_config: document_config(),
          avatar_config: avatar_config()
        )
      end)

    %{
      apply?: apply?,
      delete_legacy?: delete_legacy?,
      scanned: length(items),
      planned: Enum.count(results, &match?({:planned, _item}, &1)),
      migrated: Enum.count(results, &match?({:migrated, _item}, &1)),
      migrated_with_warnings:
        Enum.count(results, &match?({:migrated_with_warnings, _item, _}, &1)),
      skipped: Enum.count(results, &match?({:skipped, _item, _}, &1)),
      failed: Enum.count(results, &match?({:error, _item, _}, &1)),
      results: results
    }
  end

  def migrate_item(%Item{} = item, options) do
    if Keyword.get(options, :apply, false) do
      apply_item(item, options)
    else
      {:planned, item}
    end
  end

  def invoice_item(%FinanceInvoice{} = invoice, bucket \\ document_bucket()) do
    file_key = get_in(invoice.params || %{}, ["file_key"])

    cond do
      not is_binary(file_key) ->
        nil

      is_nil(invoice.organization_id) ->
        nil

      String.starts_with?(file_key, "organizations/#{invoice.organization_id}/") ->
        nil

      String.starts_with?(file_key, "invoices/") ->
        %Item{
          kind: :invoice,
          record: invoice,
          source_bucket: bucket,
          source_key: file_key,
          destination_bucket: bucket,
          destination_key:
            OwnershipKeys.tenant_object(%{organization_id: invoice.organization_id}, file_key),
          persisted_value: file_key
        }

      true ->
        nil
    end
  end

  def avatar_item(%User{} = user, bucket \\ avatar_bucket()) do
    with avatar_url when is_binary(avatar_url) <- user.avatar_url,
         {:ok, source_key} <- legacy_avatar_key(user.id, avatar_url, bucket) do
      %Item{
        kind: :avatar,
        record: user,
        source_bucket: bucket,
        source_key: source_key,
        destination_bucket: bucket,
        destination_key:
          OwnershipKeys.user_object(%{user_id: user.id}, legacy_avatar_tail(user.id, source_key)),
        persisted_value: avatar_url
      }
    else
      _ -> nil
    end
  end

  def legacy_avatar_key(user_id, value, bucket) when is_binary(value) do
    key =
      cond do
        String.starts_with?(value, "users/#{user_id}/avatars/") ->
          nil

        String.starts_with?(value, "avatars/#{user_id}/") ->
          value

        String.contains?(value, "/#{bucket}/") ->
          value
          |> String.split("/#{bucket}/", parts: 2)
          |> List.last()

        true ->
          nil
      end

    if is_binary(key) and String.starts_with?(key, "avatars/#{user_id}/"),
      do: {:ok, key},
      else: {:error, :not_legacy_avatar}
  end

  defp invoice_items(limit) do
    FinanceInvoice
    |> where([invoice], not is_nil(invoice.organization_id))
    |> where([invoice], fragment("?->>'file_key' LIKE 'invoices/%'", invoice.params))
    |> maybe_limit(limit)
    |> Repo.all()
    |> Enum.map(&invoice_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp avatar_items(limit) do
    User
    |> where([user], not is_nil(user.avatar_url))
    |> where([user], like(user.avatar_url, "%/avatars/%") or like(user.avatar_url, "avatars/%"))
    |> maybe_limit(limit)
    |> Repo.all()
    |> Enum.map(&avatar_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)

  defp apply_item(%Item{} = item, options) do
    config = config_for(item.kind, options)
    object_store = Keyword.fetch!(options, :object_store)

    with {:ok, %{body: source_body}} <-
           object_store.get_object(config, item.source_bucket, item.source_key),
         :ok <-
           ensure_verified_destination(
             object_store,
             config,
             item.destination_bucket,
             item.destination_key,
             source_body
           ),
         {:ok, _record} <- persist_item(item) do
      maybe_delete_legacy(item, options, config)
    else
      {:error, reason} -> {:error, item, reason}
      error -> {:error, item, error}
    end
  end

  defp ensure_verified_destination(object_store, config, bucket, key, source_body) do
    source_checksum = checksum(source_body)

    case object_store.get_object(config, bucket, key) do
      {:ok, %{body: destination_body}} ->
        verify_checksum(source_checksum, destination_body)

      {:error, :object_not_found} ->
        with :ok <- object_store.put_object(config, bucket, key, source_body),
             {:ok, %{body: destination_body}} <- object_store.get_object(config, bucket, key) do
          verify_checksum(source_checksum, destination_body)
        end

      error ->
        error
    end
  end

  defp verify_checksum(source_checksum, destination_body) do
    if checksum(destination_body) == source_checksum,
      do: :ok,
      else: {:error, :checksum_mismatch}
  end

  defp checksum(body), do: :crypto.hash(:sha256, body)

  defp persist_item(%Item{kind: :invoice, record: invoice, destination_key: destination_key}) do
    params = Map.put(invoice.params || %{}, "file_key", destination_key)

    RepoContext.run(%{organization_id: invoice.organization_id}, fn ->
      invoice
      |> Changeset.change(params: params)
      |> Repo.update()
    end)
  end

  defp persist_item(%Item{
         kind: :avatar,
         record: user,
         destination_bucket: bucket,
         destination_key: key
       }) do
    user
    |> Changeset.change(avatar_url: avatar_public_url(bucket, key))
    |> Repo.update()
  end

  defp maybe_delete_legacy(item, options, config) do
    if Keyword.get(options, :delete_legacy, false) do
      object_store = Keyword.fetch!(options, :object_store)

      case object_store.delete_object(config, item.source_bucket, item.source_key) do
        :ok -> {:migrated, item}
        {:error, reason} -> {:migrated_with_warnings, item, {:legacy_delete_failed, reason}}
        error -> {:migrated_with_warnings, item, {:legacy_delete_failed, error}}
      end
    else
      {:migrated, item}
    end
  end

  defp config_for(:invoice, options), do: Keyword.fetch!(options, :document_config)
  defp config_for(:avatar, options), do: Keyword.fetch!(options, :avatar_config)

  defp legacy_avatar_tail(user_id, source_key) do
    String.replace_prefix(source_key, "avatars/#{user_id}/", "avatars/")
  end

  defp document_config, do: build_config(minio_endpoint())
  defp avatar_config, do: build_config(minio_endpoint())

  defp build_config(endpoint) do
    uri = URI.parse(endpoint)

    ExAws.Config.new(:s3,
      access_key_id: Application.get_env(:milos_training, :minio_access_key, "minioadmin"),
      secret_access_key: Application.get_env(:milos_training, :minio_secret_key, "minioadmin"),
      scheme: "#{uri.scheme}://",
      host: uri.host,
      port: uri.port,
      region: "us-east-1"
    )
  end

  defp document_bucket,
    do: Application.get_env(:milos_training, :minio_bucket, "milos-invoices")

  defp avatar_bucket,
    do: Application.get_env(:milos_training, :minio_avatar_bucket, "milos-avatars")

  defp avatar_public_url(bucket, key) do
    "#{String.trim_trailing(public_endpoint(), "/")}/#{bucket}/#{key}"
  end

  defp minio_endpoint,
    do: Application.get_env(:milos_training, :minio_endpoint, "http://localhost:9000")

  defp public_endpoint,
    do: Application.get_env(:milos_training, :minio_public_endpoint) || minio_endpoint()
end
