defmodule MilosTraining.Repo.Migrations.ScopeExecutionAdminModeBypassByOrganization do
  use Ecto.Migration

  def up do
    execute(
      "DROP POLICY IF EXISTS workout_executions_owner_or_tenant_policy ON workout_executions"
    )

    execute("""
    CREATE POLICY workout_executions_owner_or_tenant_policy ON workout_executions
    USING (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
      OR (
        current_setting('app.admin_mode', true) = 'true'
        AND EXISTS (
          SELECT 1
          FROM organization_memberships om
          WHERE om.organization_id = workout_executions.organization_id
            AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
            AND om.role IN ('owner', 'admin', 'coach')
            AND om.status = 'active'
        )
      )
      OR current_setting('app.execution_authorization_check', true) = 'true'
    )
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)
  end

  def down do
    execute(
      "DROP POLICY IF EXISTS workout_executions_owner_or_tenant_policy ON workout_executions"
    )

    execute("""
    CREATE POLICY workout_executions_owner_or_tenant_policy ON workout_executions
    USING (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
      OR current_setting('app.admin_mode', true) = 'true'
      OR current_setting('app.execution_authorization_check', true) = 'true'
    )
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)
  end
end
