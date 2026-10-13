defmodule MilosTraining.Content do
  @moduledoc """
  Content context (ADR-098): on-demand video items. Member access goes through
  `Application.ListOnDemandVideos`, which checks the package.
  """

  alias MilosTraining.Content.ContentStore

  def list_videos(context, opts \\ []), do: ContentStore.list_videos(context, opts)
  def get_video(context, id), do: ContentStore.get_video(context, id)
  def create_video(context, params), do: ContentStore.create_video(context, params)
  def update_video(context, id, params), do: ContentStore.update_video(context, id, params)

  def set_video_published(context, id, published?),
    do: ContentStore.set_video_published(context, id, published?)

  def archive_video(context, id), do: ContentStore.archive_video(context, id)

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: MilosTraining.Content.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
