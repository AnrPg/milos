defmodule Palee.Imports.Domain.TenantDataPolicy do
  @moduledoc """
  Imports tenant data retention and purge policy (ADR-117, ADR-254).

  An import keeps the uploaded rows (people's names, emails, phones and
  history from another system) only to preview, apply, retry and undo
  them. They are operational data with no retention obligation: what an
  import wrote lives on in the contexts it wrote to (Finance, Facility,
  Organizations), under their own policies. Purged early: nothing points
  at these tables.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "imports",
            purge_order: 6,
            disposition: :purge,
            basis:
              "Uploaded rows and the record of imported people exist to preview, apply, retry and undo an import; what the import wrote is governed by the contexts it wrote to.",
            tables: [
              %{table: "import_rows"},
              %{table: "imported_people"},
              %{table: "imports"}
            ]
          })

  def policy, do: @policy
end
