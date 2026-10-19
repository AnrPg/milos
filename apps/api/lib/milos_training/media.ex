defmodule MilosTraining.Media do
  @moduledoc """
  Media bounded context (ADR-148): uploaded images and their lifecycle
  (pending → ready → attached → deleted). A gym owns box and post photos; a
  person owns body photos. Consumers (Organizations, Community, Wellbeing)
  keep media ids and attach or release them through this API; unattached
  uploads are swept after a day.
  """

  alias MilosTraining.Media.Domain.{ImageInspector, MediaPolicy, TenantDataPolicy}
  alias MilosTraining.Media.MediaStore

  defdelegate purposes(), to: MediaPolicy
  defdelegate content_types(), to: MediaPolicy
  defdelegate max_bytes(), to: MediaPolicy
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
  defdelegate set_attached(context, scope, ids, at), to: MediaStore
  defdelegate delete(context, scope, ids), to: MediaStore
  defdelegate list_unattached(context, scope, before), to: MediaStore
  defdelegate account_orphan_owner_ids(before), to: MediaStore

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
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
