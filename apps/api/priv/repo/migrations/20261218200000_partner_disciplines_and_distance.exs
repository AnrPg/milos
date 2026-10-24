defmodule Palee.Repo.Migrations.PartnerDisciplinesAndDistance do
  @moduledoc """
  Partners filters (vision §7.2, ADR-197):

  * `partner_profiles.disciplines`: up to five keys of the box vocabulary a
    member names in their Partners profile.
  * `palee_partner_people_within(people, radius_m)`: which of `people` have
    their main «Η περιοχή μου» neighbourhood within `radius_m` of the
    caller's own (`app.user_id`). Only people who show in Γύρω μου
    (`visible_around`) count, at their neighbourhood's centroid, as their
    posts do; it answers ids, never a place or a distance.
  """

  use Ecto.Migration

  def up do
    alter table(:partner_profiles) do
      add :disciplines, {:array, :string}, null: false, default: []
    end

    execute("""
    CREATE FUNCTION palee_partner_people_within(p_people uuid[], p_radius_m double precision)
    RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT a.user_id
      FROM public.user_home_areas me
      JOIN public.places_neighbourhoods mine ON mine.id = me.neighbourhood_id
      JOIN public.user_home_areas a ON a.position = 0 AND a.user_id = ANY (p_people)
      JOIN public.places_neighbourhoods n ON n.id = a.neighbourhood_id
      JOIN public.community_social_settings ss ON ss.user_id = a.user_id AND ss.visible_around
      WHERE me.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
        AND me.position = 0
        AND a.user_id <> me.user_id
        AND ST_DWithin(
              palee_geo_point(n.latitude, n.longitude),
              palee_geo_point(mine.latitude, mine.longitude),
              p_radius_m)
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_partner_people_within(uuid[], double precision)")

    alter table(:partner_profiles) do
      remove :disciplines
    end
  end
end
