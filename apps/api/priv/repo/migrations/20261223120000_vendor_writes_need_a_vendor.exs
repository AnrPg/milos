defmodule Palee.Repo.Migrations.VendorWritesNeedAVendor do
  use Ecto.Migration

  # TD-205: vendors_tenant_policy used one predicate for reads and writes,
  # `user_id = app.user_id OR palee_acting_user_is_vendor()`, and its WITH CHECK
  # also admitted any session without `app.user_id`. So a session scoped to a
  # user could make that user a vendor, and an unscoped one could make anyone
  # a vendor. Reads stay as they were (an account sees its own row, vendors see
  # all, as does the operator scope, since an upsert must also read the row);
  # writes now need an active vendor, or the operator scope `app.vendor_grant`
  # that only the grant/revoke tasks set.
  #
  # palee_acting_user_is_vendor() reads vendors itself. Called from a vendors
  # policy it was subject to that same policy again; as SECURITY DEFINER (owned
  # by the migration role, which bypasses RLS) it reads the table directly.

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @writer "palee_acting_user_is_vendor() OR current_setting('app.vendor_grant', true) = 'true'"

  def up do
    execute("ALTER FUNCTION palee_acting_user_is_vendor() SECURITY DEFINER")
    execute("ALTER FUNCTION palee_acting_user_is_vendor() SET search_path = pg_catalog, public")

    execute("DROP POLICY IF EXISTS vendors_tenant_policy ON vendors")

    execute("""
    CREATE POLICY vendors_read_policy ON vendors FOR SELECT
    USING (vendors.user_id = #{@acting_user} OR #{@writer})
    """)

    execute("CREATE POLICY vendors_insert_policy ON vendors FOR INSERT WITH CHECK (#{@writer})")

    execute("""
    CREATE POLICY vendors_update_policy ON vendors FOR UPDATE
    USING (#{@writer}) WITH CHECK (#{@writer})
    """)

    execute("CREATE POLICY vendors_delete_policy ON vendors FOR DELETE USING (#{@writer})")
  end

  def down do
    for policy <- ~w(read insert update delete) do
      execute("DROP POLICY IF EXISTS vendors_#{policy}_policy ON vendors")
    end

    execute("""
    CREATE POLICY vendors_tenant_policy ON vendors
    USING (vendors.user_id = #{@acting_user} OR palee_acting_user_is_vendor())
    WITH CHECK (
      #{@acting_user} IS NULL
      OR vendors.user_id = #{@acting_user}
      OR palee_acting_user_is_vendor()
    )
    """)

    execute("ALTER FUNCTION palee_acting_user_is_vendor() RESET search_path")
    execute("ALTER FUNCTION palee_acting_user_is_vendor() SECURITY INVOKER")
  end
end
