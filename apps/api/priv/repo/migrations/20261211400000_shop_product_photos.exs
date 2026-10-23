defmodule Palee.Repo.Migrations.ShopProductPhotos do
  @moduledoc "ADR-190: `shop_product_photo` media of a business (public, inspected like box photos)."

  use Ecto.Migration

  def up, do: purposes(~w(box_photo shop_product_photo))

  def down do
    execute("DELETE FROM media_tenant_objects WHERE purpose = 'shop_product_photo'")
    purposes(~w(box_photo))
  end

  defp purposes(list) do
    execute("ALTER TABLE media_tenant_objects DROP CONSTRAINT media_tenant_objects_purpose_check")

    create constraint(:media_tenant_objects, :media_tenant_objects_purpose_check,
             check: "purpose IN (#{Enum.map_join(list, ", ", &"'#{&1}'")})"
           )
  end
end
