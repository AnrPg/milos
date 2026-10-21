defmodule Palee.Repo.Migrations.NutritionPortions do
  use Ecto.Migration

  @moduledoc """
  ADR-159 (board 14, Q4 and Q5): the coach's plan gains daily hand portions
  (palm of protein, cupped hand of carbs, fist of vegetables, thumb of fat; halves
  allowed) and, optionally, the meal slots the member logs against. Grams
  stay as the coach wrote them; calories stay staff-only.

  Ευεξία is read in the member's personal session, where tenant tables are
  closed, so `palee_own_nutrition_plans()` answers the caller's own plans in
  gyms where they are an active member, without calories or the plan text.
  """

  @slots ~w(breakfast morning_snack lunch afternoon_snack dinner evening_snack snack pre_workout post_workout)

  def up do
    alter table(:nutrition_plans) do
      add :portion_targets, :map
      add :meal_slots, {:array, :text}, null: false, default: []
    end

    execute("""
    ALTER TABLE nutrition_plans ADD CONSTRAINT nutrition_plans_meal_slots_check
      CHECK (meal_slots <@ ARRAY[#{Enum.map_join(@slots, ", ", &"'#{&1}'")}]::text[])
    """)

    execute("""
    ALTER TABLE nutrition_plans ADD CONSTRAINT nutrition_plans_portion_targets_check
      CHECK (portion_targets IS NULL OR jsonb_typeof(portion_targets) = 'object')
    """)

    execute("""
    CREATE FUNCTION palee_own_nutrition_plans()
    RETURNS TABLE (
      id uuid, organization_id uuid, title varchar, protein_grams integer,
      carbs_grams integer, fat_grams integer, portion_targets jsonb,
      meal_slots text[], updated_at timestamp
    )
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT p.id, p.organization_id, p.title, p.protein_grams, p.carbs_grams,
             p.fat_grams, p.portion_targets, p.meal_slots, p.updated_at
      FROM public.nutrition_plans p
      JOIN public.organization_memberships m
        ON m.organization_id = p.organization_id AND m.user_id = p.user_id
       AND m.status = 'active'
      WHERE p.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      ORDER BY p.updated_at DESC
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_own_nutrition_plans()")

    alter table(:nutrition_plans) do
      remove :portion_targets
      remove :meal_slots
    end
  end
end
