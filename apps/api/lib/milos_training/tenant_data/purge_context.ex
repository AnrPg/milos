defmodule MilosTraining.TenantData.PurgeContext do
  @moduledoc """
  Explicit tenant scope for the reviewed export/purge workflow (ADR-117).

  It is only ever built by `MilosTraining.Organizations.tenant_purge_context/2`
  for an organization with an open purge record, so a context's
  `export_tenant_data/1` or `purge_tenant_data/1` can never be reached with an
  ordinary request or job tenant context.

  * `organization_id` - tenant being exported/purged; becomes `app.organization_id`.
  * `user_id` - acting vendor; becomes `app.user_id` so vendor-scoped root
    tables stay readable under RLS.
  * `subject_user_ids` - every account with a membership in the tenant; used to
    open per-user sessions for personal tables whose RLS keys on `user_id` only.
  """

  @enforce_keys [:organization_id, :purge_id, :user_id]
  defstruct [:organization_id, :purge_id, :user_id, subject_user_ids: [], source: :tenant_purge]

  @type t :: %__MODULE__{
          organization_id: Ecto.UUID.t(),
          purge_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          subject_user_ids: [Ecto.UUID.t()],
          source: :tenant_purge
        }
end
