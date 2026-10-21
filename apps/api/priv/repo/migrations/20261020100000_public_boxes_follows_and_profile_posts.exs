defmodule Palee.Repo.Migrations.PublicBoxesFollowsAndProfilePosts do
  use Ecto.Migration

  # ADR-142 (P2-M2): the public box page, follows and post audiences.
  #
  # 1. Two SECURITY DEFINER lookups expose exactly what a visitor may know
  #    about a gym before any tenant scope exists: whether a slug (or one of
  #    its aliases) names an active gym with a published page, and the public
  #    face (name, logo, colour) of published gyms by id. Everything else on
  #    the page is read inside that gym's scope and projected by the
  #    application to the published snapshot.
  # 2. community_follows is account-scoped: the follower owns the row
  #    (`user_id`), the followed person reads, accepts (UPDATE) and removes
  #    (DELETE) the rows that target them. Counts others may see come from a
  #    SECURITY DEFINER helper that returns numbers only.
  # 3. Posts to followers or to everyone belong to their author, not to a gym
  #    (the athlete's voice follows them across gyms, vision §4.9), so they
  #    live in account-scoped community_profile_posts with their own kudos
  #    and comments. A club post stays a tenant row; staff may also make one
  #    public (it then shows on the box page and to the box's followers).

  @profile_tables ~w(
    community_profile_posts
    community_profile_post_reactions
    community_profile_post_comments
  )

  @notification_types ~w(
    booking_approved booking_rejected booking_pending booking_timeout workout_note
    workout_changed workout_deleted workout_rejected workout_moved workout_assigned
    workout_assignment_requested review_submitted athlete_message workout_completed
    coaching_message box_message challenge_completed chat_message invoice_issued
    payment_reminder booking_waitlist_promoted package_expiring form_review_submitted
    form_review_completed coaching_reply_overdue nutrition_plan_updated appointment_booked
    appointment_cancelled coach_client_assigned coach_note_viewed inventory_repair_needed
    inventory_stock_low inventory_digest subscription_expiring subscription_grace access_ended
  )

  @new_notification_types ~w(follow_requested follow_accepted)

  def up do
    # Board 4 Q4: the owner picks which coaches the page shows.
    alter table(:organization_public_profiles) do
      add :coach_ids, {:array, :binary_id}, null: false, default: []
    end

    public_box_lookups()
    follows()
    profile_posts()
    public_club_posts()
    replace_notification_types(@notification_types ++ @new_notification_types)
  end

  def down do
    replace_notification_types(@notification_types)

    for table <- ~w(community_posts community_post_reactions community_post_comments) do
      execute("DROP POLICY IF EXISTS #{table}_public_read_policy ON #{table}")
    end

    for table <- Enum.reverse(@profile_tables), do: drop(table(table))
    execute("DROP FUNCTION IF EXISTS palee_follow_counts(text, uuid[])")
    execute("DROP FUNCTION IF EXISTS palee_following_count(uuid)")
    drop table(:community_follows)
    execute("DROP FUNCTION IF EXISTS palee_public_boxes(uuid[])")
    execute("DROP FUNCTION IF EXISTS palee_public_box_by_slug(text)")

    alter table(:organization_public_profiles) do
      remove :coach_ids
    end
  end

  defp public_box_lookups do
    # A slug, a current slug or any alias it ever had, resolves only for an
    # active gym that has published its page.
    execute("""
    CREATE OR REPLACE FUNCTION palee_public_box_by_slug(box_slug text)
    RETURNS TABLE (organization_id uuid, slug text)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id, o.slug::text
      FROM public.organizations o
      JOIN public.organization_public_profiles p ON p.organization_id = o.id
      WHERE o.status = 'active'
        AND p.published_at IS NOT NULL
        AND (o.slug = box_slug
             OR o.id = (SELECT a.organization_id
                        FROM public.organization_slug_aliases a
                        WHERE a.slug = box_slug))
      LIMIT 1
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_public_boxes(org_ids uuid[])
    RETURNS TABLE (organization_id uuid, slug text, name text, logo_url text, primary_color text)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id, o.slug::text, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text
      FROM public.organizations o
      JOIN public.organization_public_profiles p ON p.organization_id = o.id
      LEFT JOIN public.organization_settings s ON s.organization_id = o.id
      WHERE o.id = ANY (org_ids)
        AND o.status = 'active'
        AND p.published_at IS NOT NULL
    $$
    """)
  end

  defp follows do
    create table(:community_follows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # The follower: the account that owns the row.
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :target_type, :string, null: false
      add :target_id, :binary_id, null: false
      add :status, :string, null: false
      add :accepted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:community_follows, :community_follows_target_type_check,
             check: "target_type IN ('user', 'organization', 'club')"
           )

    create constraint(:community_follows, :community_follows_status_check,
             check: "status IN ('requested', 'active')"
           )

    create constraint(:community_follows, :community_follows_not_self,
             check: "target_type <> 'user' OR target_id <> user_id"
           )

    create unique_index(:community_follows, [:user_id, :target_type, :target_id])
    create index(:community_follows, [:target_type, :target_id, :status])

    owner = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    target =
      "target_type = 'user' AND target_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    # The follower reads and removes their rows and creates them; a follow of
    # a person can only start as a request. Only the followed person accepts.
    execute(
      "CREATE POLICY community_follows_owner_read_policy ON community_follows FOR SELECT USING (#{owner})"
    )

    execute("""
    CREATE POLICY community_follows_owner_insert_policy ON community_follows
    FOR INSERT WITH CHECK (#{owner} AND (target_type <> 'user' OR status = 'requested'))
    """)

    execute(
      "CREATE POLICY community_follows_owner_remove_policy ON community_follows FOR DELETE USING (#{owner})"
    )

    execute(
      "CREATE POLICY community_follows_target_read_policy ON community_follows FOR SELECT USING (#{target})"
    )

    # The followed person accepts a request; they can only make it active.
    execute("""
    CREATE POLICY community_follows_target_accept_policy ON community_follows
    FOR UPDATE USING (#{target}) WITH CHECK (#{target} AND status = 'active')
    """)

    execute(
      "CREATE POLICY community_follows_target_remove_policy ON community_follows FOR DELETE USING (#{target})"
    )

    secure_personal(:community_follows)

    # Followers of each target, active only; what anyone may see on a profile.
    execute("""
    CREATE OR REPLACE FUNCTION palee_follow_counts(kind text, ids uuid[])
    RETURNS TABLE (target_id uuid, followers bigint)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT f.target_id, count(*)
      FROM public.community_follows f
      WHERE f.target_type = kind AND f.target_id = ANY (ids) AND f.status = 'active'
      GROUP BY f.target_id
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_following_count(account uuid)
    RETURNS bigint
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT count(*) FROM public.community_follows f
      WHERE f.user_id = account AND f.status = 'active'
    $$
    """)
  end

  defp profile_posts do
    create table(:community_profile_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # The author.
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :audience, :string, null: false
      add :body, :text
      add :attachment_type, :string
      add :attachment_id, :binary_id
      add :attachment, :map
      add :client_operation_id, :string
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:community_profile_posts, :community_profile_posts_audience_check,
             check: "audience IN ('followers', 'public')"
           )

    create constraint(:community_profile_posts, :community_profile_posts_attachment_check,
             check:
               "(attachment_type IS NULL AND attachment_id IS NULL AND attachment IS NULL) OR " <>
                 "(attachment_type IN ('training_log_entry', 'workout_execution', 'pr') AND attachment_id IS NOT NULL AND attachment IS NOT NULL)"
           )

    create constraint(:community_profile_posts, :community_profile_posts_content_check,
             check:
               "attachment_type IS NOT NULL OR (body IS NOT NULL AND length(btrim(body)) > 0)"
           )

    create unique_index(:community_profile_posts, [:user_id, :client_operation_id],
             where: "client_operation_id IS NOT NULL",
             name: :community_profile_posts_client_operation_index
           )

    create index(:community_profile_posts, [:user_id, :inserted_at, :id],
             where: "deleted_at IS NULL"
           )

    create index(:community_profile_posts, [:audience, :inserted_at, :id],
             where: "deleted_at IS NULL"
           )

    create table(:community_profile_post_reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id,
          references(:community_profile_posts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "kudos"

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:community_profile_post_reactions, :community_profile_post_reactions_kind,
             check: "kind IN ('kudos')"
           )

    create unique_index(:community_profile_post_reactions, [:post_id, :user_id, :kind])

    create table(:community_profile_post_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id,
          references(:community_profile_posts, type: :binary_id, on_delete: :delete_all),
          null: false

      # The comment's author.
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:community_profile_post_comments, [:post_id, :inserted_at])

    me = "NULLIF(current_setting('app.user_id', true), '')::uuid"

    # Everyone reads a public post; an active follower reads a followers post.
    execute("""
    CREATE POLICY community_profile_posts_owner_policy ON community_profile_posts
    USING (user_id = #{me}) WITH CHECK (user_id = #{me})
    """)

    execute("""
    CREATE POLICY community_profile_posts_audience_read_policy ON community_profile_posts
    FOR SELECT USING (
      deleted_at IS NULL AND (
        audience = 'public' OR EXISTS (
          SELECT 1 FROM community_follows f
          WHERE f.user_id = #{me} AND f.target_type = 'user'
            AND f.target_id = community_profile_posts.user_id AND f.status = 'active')))
    """)

    # Kudos and comments: on posts the session can read (the posts policy
    # applies inside the subquery); the post's author can remove comments.
    readable =
      "EXISTS (SELECT 1 FROM community_profile_posts p WHERE p.id = post_id AND p.deleted_at IS NULL)"

    for table <- ~w(community_profile_post_reactions community_profile_post_comments) do
      execute("""
      CREATE POLICY #{table}_owner_policy ON #{table}
      USING (user_id = #{me}) WITH CHECK (user_id = #{me} AND #{readable})
      """)

      execute("CREATE POLICY #{table}_read_policy ON #{table} FOR SELECT USING (#{readable})")
    end

    execute("""
    CREATE POLICY community_profile_post_comments_post_author_policy ON community_profile_post_comments
    FOR UPDATE USING (EXISTS (
      SELECT 1 FROM community_profile_posts p WHERE p.id = post_id AND p.user_id = #{me}))
    """)

    Enum.each(@profile_tables, &secure_personal/1)
  end

  # A club post staff made public is readable by anyone, with its kudos and
  # comments; writing still happens in the gym's scope.
  defp public_club_posts do
    execute("""
    CREATE POLICY community_posts_public_read_policy ON community_posts
    FOR SELECT USING (audience = 'public' AND deleted_at IS NULL AND hidden_at IS NULL)
    """)

    public_post =
      "EXISTS (SELECT 1 FROM community_posts p WHERE p.id = post_id AND p.audience = 'public' " <>
        "AND p.deleted_at IS NULL AND p.hidden_at IS NULL)"

    for table <- ~w(community_post_reactions community_post_comments) do
      execute(
        "CREATE POLICY #{table}_public_read_policy ON #{table} FOR SELECT USING (#{public_post})"
      )
    end
  end

  defp secure_personal(table) do
    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end
end
