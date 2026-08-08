defmodule MilosTraining.Repo.Migrations.AddUniqueReviewTargetPerUser do
  use Ecto.Migration

  def up do
    alter table(:reviews) do
      add :review_identity_key, :text
    end

    execute("""
    WITH ranked_reviews AS (
      SELECT id,
             organization_id,
             user_id,
             target_type,
             target_id,
             row_number() OVER (
               PARTITION BY organization_id, user_id, target_type, target_id
               ORDER BY inserted_at ASC, id ASC
             ) AS row_number
      FROM reviews
      WHERE target_id IS NOT NULL
    )
    UPDATE reviews AS review
    SET review_identity_key =
      CASE
        WHEN ranked.row_number = 1 THEN
          ranked.user_id::text || ':' || ranked.target_type || ':' || ranked.target_id::text
        ELSE
          ranked.user_id::text || ':' || ranked.target_type || ':' || ranked.target_id::text ||
          ':legacy-duplicate:' || review.id::text
      END
    FROM ranked_reviews AS ranked
    WHERE review.id = ranked.id
    """)

    create unique_index(:reviews, [:organization_id, :review_identity_key],
             name: :reviews_one_per_user_target_index,
             where: "review_identity_key IS NOT NULL"
           )
  end

  def down do
    drop_if_exists index(:reviews, [:organization_id, :review_identity_key],
                     name: :reviews_one_per_user_target_index
                   )

    alter table(:reviews) do
      remove :review_identity_key
    end
  end
end
