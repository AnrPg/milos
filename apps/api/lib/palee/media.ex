defmodule Palee.Media do
  @moduledoc """
  Media bounded context (ADR-148, ADR-157): uploaded images and videos and
  their lifecycle (pending → [processing →] ready | rejected → attached →
  deleted). A gym owns box photos; a person owns body photos and the photos
  and videos they post. Consumers (Organizations, Community, Body) keep
  media ids and attach or release them through this API; unattached uploads
  are swept after a day.
  """

  alias Palee.Media.Domain.{ImageInspector, MediaPolicy, TenantDataPolicy}
  alias Palee.Media.MediaStore

  defdelegate purposes(), to: MediaPolicy
  defdelegate post_purposes(), to: MediaPolicy
  defdelegate statuses(), to: MediaPolicy
  defdelegate content_types(), to: MediaPolicy
  defdelegate content_types(purpose), to: MediaPolicy
  defdelegate post_content_types(), to: MediaPolicy
  defdelegate max_bytes(), to: MediaPolicy
  defdelegate max_bytes(purpose), to: MediaPolicy
  defdelegate kind(purpose), to: MediaPolicy
  defdelegate processing(purpose), to: MediaPolicy
  defdelegate variant_key(object_key, name, extension), to: MediaPolicy
  defdelegate validate_upload(purpose, sniffed_type, byte_size), to: MediaPolicy
  defdelegate validate_image(probe), to: MediaPolicy
  defdelegate validate_video(probe), to: MediaPolicy
  defdelegate image_spec(), to: MediaPolicy
  defdelegate video_spec(), to: MediaPolicy
  defdelegate check_quota(usage), to: MediaPolicy
  defdelegate rejection?(reason), to: MediaPolicy
  defdelegate max_video_ms(), to: MediaPolicy
  defdelegate sniff(head), to: ImageInspector
  defdelegate probe_bytes(), to: MediaPolicy
  defdelegate scope(purpose), to: MediaPolicy
  defdelegate bucket(purpose), to: MediaPolicy
  defdelegate public?(purpose), to: MediaPolicy
  defdelegate orphan_after_seconds(), to: MediaPolicy
  defdelegate allocate(purpose, content_type, byte_size, id), to: MediaPolicy
  defdelegate validate_stored(content_type, inspected, byte_size), to: MediaPolicy
  defdelegate inspect_image(head), to: ImageInspector

  defdelegate create(context, scope, attrs), to: MediaStore
  defdelegate get(context, scope, id), to: MediaStore
  defdelegate list(context, scope, ids), to: MediaStore
  defdelegate mark_ready(context, scope, id, attrs), to: MediaStore
  defdelegate mark_processing(context, scope, id, attrs), to: MediaStore
  defdelegate mark_processed(context, scope, id, attrs), to: MediaStore
  defdelegate mark_rejected(context, scope, id, reason), to: MediaStore
  defdelegate set_attached(context, scope, ids, at), to: MediaStore
  defdelegate attach(context, scope, ids, attachment, at), to: MediaStore
  defdelegate update_alt_text(context, scope, id, text), to: MediaStore
  defdelegate usage(context, scope, since), to: MediaStore
  defdelegate delete(context, scope, ids), to: MediaStore
  defdelegate list_unattached(context, scope, before), to: MediaStore
  defdelegate list_ids_by_purpose(context, scope, purpose), to: MediaStore
  defdelegate account_orphan_owner_ids(before), to: MediaStore
  defdelegate dangling_post_media(before, limit), to: MediaStore
  defdelegate stale_post_media(before, limit), to: MediaStore

  @doc "Every stored object of a media item: the upload and its renditions."
  def object_keys(%{object_key: key, variants: variants}) do
    rendition_keys =
      for {_name, %{"key" => rendition_key}} <- variants || %{}, do: rendition_key

    Enum.uniq([key | rendition_keys])
  end

  def object_keys(%{object_key: key}), do: [key]

  @doc """
  The ready media among `ids`, in the given order, all of `purpose`;
  `{:error, :invalid_media}` when any id is unknown, pending or of another
  purpose.
  """
  def fetch_ready(context, purpose, ids) when is_list(ids) do
    scope = MediaPolicy.scope(purpose)
    found = context |> list(scope, ids) |> Map.new(&{&1.id, &1})

    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case Map.get(found, id) do
        %{status: "ready", purpose: ^purpose} = media -> {:cont, {:ok, [media | acc]}}
        _missing -> {:halt, {:error, :invalid_media}}
      end
    end)
    |> case do
      {:ok, media} -> {:ok, Enum.reverse(media)}
      error -> error
    end
  end

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
