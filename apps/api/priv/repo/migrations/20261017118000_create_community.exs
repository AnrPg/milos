defmodule MilosTraining.Repo.Migrations.CreateCommunity do
  use Ecto.Migration

  # ADR-138: the Community context. Clubs (a gym's own club first), their
  # channels, explicit memberships and preferences, posts, reactions and
  # comments. Every row belongs to the gym that runs the club, so rows are
  # tenant-scoped like any other; a member also reads the clubs of every gym
  # they belong to from their personal session (the cross-gym feed).
  #
  # A gym club's membership is the gym's own active membership list: it is
  # never copied. community_club_memberships holds what a member chose about
  # a club (notification level) and, for the club kinds that are not derived
  # (Phase 2), the membership itself.
  @tables ~w(
    community_clubs
    community_channels
    community_club_memberships
    community_channel_memberships
    community_posts
    community_post_reactions
    community_post_comments
  )

  def change do
    create table(:community_clubs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :name, :string
      add :join_policy, :string, null: false, default: "members_only"
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:community_clubs, :community_clubs_kind_check,
             check: "kind IN ('gym', 'open', 'member_group', 'pt_squad', 'season')"
           )

    create constraint(:community_clubs, :community_clubs_join_policy_check,
             check: "join_policy IN ('members_only', 'open', 'approval', 'invite')"
           )

    # A gym club takes the gym's own name; every other club names itself.
    create constraint(:community_clubs, :community_clubs_name_check,
             check: "kind = 'gym' OR (name IS NOT NULL AND length(btrim(name)) > 0)"
           )

    create unique_index(:community_clubs, [:id, :organization_id],
             name: :community_clubs_id_organization_index
           )

    create unique_index(:community_clubs, [:organization_id],
             where: "kind = 'gym'",
             name: :community_clubs_one_gym_club_index
           )

    create table(:community_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :club_id, :binary_id, null: false
      add :kind, :string, null: false
      add :name, :string
      add :write_policy, :string, null: false
      add :membership, :string, null: false
      add :context_type, :string
      add :context_id, :binary_id
      add :position, :integer, null: false, default: 0
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    composite_fk(:community_channels, :club_id, :community_clubs)

    create constraint(:community_channels, :community_channels_kind_check,
             check:
               "kind IN ('announcements', 'wod', 'challenges', 'class_slot', 'season', 'custom')"
           )

    create constraint(:community_channels, :community_channels_write_policy_check,
             check: "write_policy IN ('staff', 'members', 'participants', 'system_and_members')"
           )

    create constraint(:community_channels, :community_channels_membership_check,
             check: "membership IN ('everyone', 'opt_in', 'invite')"
           )

    # Built-in channels are named by their kind (and translated by clients);
    # a custom or class-slot channel carries its own name.
    create constraint(:community_channels, :community_channels_name_check,
             check:
               "kind IN ('announcements', 'wod', 'challenges') OR (name IS NOT NULL AND length(btrim(name)) > 0)"
           )

    create constraint(:community_channels, :community_channels_context_check,
             check: "(context_type IS NULL) = (context_id IS NULL)"
           )

    create unique_index(:community_channels, [:id, :organization_id],
             name: :community_channels_id_organization_index
           )

    create unique_index(:community_channels, [:club_id, :kind],
             where: "kind IN ('announcements', 'wod', 'challenges')",
             name: :community_channels_one_builtin_index
           )

    create unique_index(:community_channels, [:club_id, :context_type, :context_id],
             where: "context_id IS NOT NULL",
             name: :community_channels_one_per_context_index
           )

    create table(:community_club_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :club_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :notify_level, :string, null: false, default: "all"
      timestamps(type: :utc_datetime_usec)
    end

    composite_fk(:community_club_memberships, :club_id, :community_clubs)

    create constraint(:community_club_memberships, :community_club_memberships_role_check,
             check: "role IN ('member', 'staff')"
           )

    create constraint(:community_club_memberships, :community_club_memberships_notify_check,
             check: "notify_level IN ('all', 'announcements', 'none')"
           )

    create unique_index(:community_club_memberships, [:club_id, :user_id])
    create index(:community_club_memberships, [:user_id])

    create table(:community_channel_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :source, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    composite_fk(:community_channel_memberships, :channel_id, :community_channels)

    create constraint(:community_channel_memberships, :community_channel_memberships_source_check,
             check: "source IN ('opt_in', 'suggested', 'invited', 'auto')"
           )

    create unique_index(:community_channel_memberships, [:channel_id, :user_id])
    create index(:community_channel_memberships, [:user_id])

    create table(:community_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :club_id, :binary_id, null: false
      add :channel_id, :binary_id, null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :audience, :string, null: false, default: "club_channel"
      add :body, :text
      add :attachment_type, :string
      add :attachment_id, :binary_id
      # What the attachment showed when it was shared (ADR-138 §posts): the
      # author chose to share exactly this, so later edits stay in the journal.
      add :attachment, :map
      add :client_operation_id, :string
      add :pinned_at, :utc_datetime_usec
      add :hidden_at, :utc_datetime_usec
      add :hidden_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    composite_fk(:community_posts, :club_id, :community_clubs)
    composite_fk(:community_posts, :channel_id, :community_channels)

    create constraint(:community_posts, :community_posts_audience_check,
             check: "audience IN ('club_channel', 'followers', 'public')"
           )

    create constraint(:community_posts, :community_posts_attachment_check,
             check:
               "(attachment_type IS NULL AND attachment_id IS NULL AND attachment IS NULL) OR " <>
                 "(attachment_type IN ('training_log_entry', 'workout_execution', 'pr') AND attachment_id IS NOT NULL AND attachment IS NOT NULL)"
           )

    create constraint(:community_posts, :community_posts_content_check,
             check:
               "attachment_type IS NOT NULL OR (body IS NOT NULL AND length(btrim(body)) > 0)"
           )

    create unique_index(:community_posts, [:id, :organization_id],
             name: :community_posts_id_organization_index
           )

    create unique_index(:community_posts, [:author_id, :client_operation_id],
             where: "client_operation_id IS NOT NULL",
             name: :community_posts_client_operation_index
           )

    create index(:community_posts, [:club_id, :inserted_at, :id], where: "deleted_at IS NULL")
    create index(:community_posts, [:channel_id, :inserted_at, :id], where: "deleted_at IS NULL")
    create index(:community_posts, [:author_id, :inserted_at], where: "deleted_at IS NULL")

    create table(:community_post_reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :post_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "kudos"
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    composite_fk(:community_post_reactions, :post_id, :community_posts)

    create constraint(:community_post_reactions, :community_post_reactions_kind_check,
             check: "kind IN ('kudos')"
           )

    create unique_index(:community_post_reactions, [:post_id, :user_id, :kind])

    create table(:community_post_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :post_id, :binary_id, null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :deleted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    composite_fk(:community_post_comments, :post_id, :community_posts)
    create index(:community_post_comments, [:post_id, :inserted_at])

    for table <- @tables, do: secure(table)
  end

  defp composite_fk(table, column, parent) do
    name = "#{table}_#{column}_fkey"

    execute(
      """
      ALTER TABLE #{table}
      ADD CONSTRAINT #{name}
      FOREIGN KEY (#{column}, organization_id)
      REFERENCES #{parent} (id, organization_id) ON DELETE CASCADE
      """,
      "ALTER TABLE #{table} DROP CONSTRAINT #{name}"
    )
  end

  # Writes happen in the gym's scope. Reads are also allowed from a member's
  # personal session for every gym they actively belong to, which is how the
  # club bar and the cross-gym feed read.
  defp secure(table) do
    execute(
      """
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}"
    )

    execute(
      """
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}"
    )

    execute(
      """
      CREATE POLICY #{table}_member_read_policy ON #{table}
      FOR SELECT
      USING (milos_acting_user_belongs_to(organization_id))
      """,
      "DROP POLICY IF EXISTS #{table}_member_read_policy ON #{table}"
    )

    execute(
      "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY",
      "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
    )
  end
end
