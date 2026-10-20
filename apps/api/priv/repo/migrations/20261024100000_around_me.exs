defmodule MilosTraining.Repo.Migrations.AroundMe do
  use Ecto.Migration

  # ADR-154 (P2-M6): Γύρω μου, nearby discovery.
  #
  # - places_neighbourhoods: a gazetteer of neighbourhoods and cities with a
  #   centroid and an approximate radius. Platform reference data: everyone
  #   reads it, only migrations write it (new places are added by later
  #   migrations, keyed by `slug`, which is never renamed).
  # - user_home_areas: «Η περιοχή μου», the neighbourhoods a person searches
  #   from by default. Personal: only its owner reads it. The one exception is
  #   the posts search below, which uses only the first neighbourhood's
  #   centroid, and only for people who opted in.
  # - community_social_settings.visible_around: «Φαίνομαι στο Γύρω μου», off
  #   by default.
  # - saved_filters: an opt-in daily alert per named filter.
  # - Cross-gym discovery runs through narrow SECURITY DEFINER functions
  #   (ADR-131 §2) that answer one question: which public items match a
  #   filter near a place. They return ids, public coordinates (a gym's
  #   location, an event's place, a neighbourhood centroid) and distances;
  #   the application reads the cards through the usual policies. Each kind
  #   has an inlinable matcher (invoker rights, so calling one directly is
  #   still bound by RLS) that the definer wrappers share.
  # - GiST indexes cover every spatial predicate: gym locations (ADR-141),
  #   events with a place of their own, and neighbourhood centroids.

  @before_types ~w(
    booking_approved booking_rejected booking_pending booking_timeout workout_note
    workout_changed workout_deleted workout_rejected workout_moved workout_assigned
    workout_assignment_requested review_submitted athlete_message workout_completed
    coaching_message box_message challenge_completed chat_message invoice_issued
    payment_reminder booking_waitlist_promoted package_expiring form_review_submitted
    form_review_completed coaching_reply_overdue nutrition_plan_updated appointment_booked
    appointment_cancelled coach_client_assigned coach_note_viewed inventory_repair_needed
    inventory_stock_low inventory_digest subscription_expiring subscription_grace access_ended
    follow_requested follow_accepted trial_requested trial_booked trial_cancelled
    trial_accepted trial_declined trial_reminder trial_follow_up trial_class_cancelled
    community_group_proposed community_group_approved community_group_declined
    community_group_join_requested community_group_join_approved community_group_archive_warning
    community_report_created community_club_join_requested community_club_join_approved
    community_event_waitlist_promoted community_event_cancelled community_event_changed
    community_event_reminder community_event_guest_joined community_event_trial_offer
    community_event_message
  )

  @around_types ~w(around_new_matches)

  # {slug, name, English name, latitude, longitude, radius in metres};
  # neighbourhoods start with their city's slug.
  # Cities first: a neighbourhood names its city by slug.
  @cities [
    {"athens", "Αθήνα", "Athens", 37.9838, 23.7275, 9000},
    {"piraeus", "Πειραιάς", "Piraeus", 37.9420, 23.6460, 4000},
    {"thessaloniki", "Θεσσαλονίκη", "Thessaloniki", 40.6401, 22.9444, 7000},
    {"patras", "Πάτρα", "Patras", 38.2466, 21.7346, 5000},
    {"heraklion", "Ηράκλειο", "Heraklion", 35.3387, 25.1442, 5000},
    {"larissa", "Λάρισα", "Larissa", 39.6390, 22.4191, 4000},
    {"volos", "Βόλος", "Volos", 39.3621, 22.9420, 4000},
    {"ioannina", "Ιωάννινα", "Ioannina", 39.6650, 20.8537, 4000},
    {"chania", "Χανιά", "Chania", 35.5138, 24.0180, 4000},
    {"kalamata", "Καλαμάτα", "Kalamata", 37.0389, 22.1142, 3500},
    {"rhodes", "Ρόδος", "Rhodes", 36.4349, 28.2176, 3500}
  ]

  @neighbourhoods [
    {"athens", "Κυψέλη", "Kypseli", 38.0010, 23.7380, 900},
    {"athens", "Πατήσια", "Patisia", 38.0180, 23.7330, 1200},
    {"athens", "Κολωνάκι", "Kolonaki", 37.9780, 23.7430, 700},
    {"athens", "Εξάρχεια", "Exarchia", 37.9870, 23.7330, 700},
    {"athens", "Παγκράτι", "Pangrati", 37.9680, 23.7480, 1000},
    {"athens", "Κουκάκι", "Koukaki", 37.9640, 23.7240, 700},
    {"athens", "Πλάκα", "Plaka", 37.9720, 23.7300, 500},
    {"athens", "Μοναστηράκι", "Monastiraki", 37.9760, 23.7250, 500},
    {"athens", "Ψυρρή", "Psyrri", 37.9780, 23.7230, 400},
    {"athens", "Θησείο", "Thiseio", 37.9760, 23.7180, 500},
    {"athens", "Μεταξουργείο", "Metaxourgeio", 37.9850, 23.7200, 600},
    {"athens", "Κεραμεικός", "Kerameikos", 37.9790, 23.7130, 600},
    {"athens", "Γκάζι", "Gazi", 37.9780, 23.7110, 500},
    {"athens", "Πετράλωνα", "Petralona", 37.9690, 23.7090, 800},
    {"athens", "Κολωνός", "Kolonos", 37.9960, 23.7110, 900},
    {"athens", "Σεπόλια", "Sepolia", 38.0040, 23.7100, 800},
    {"athens", "Αμπελόκηποι", "Ampelokipoi", 37.9880, 23.7600, 900},
    {"athens", "Γουδή", "Goudi", 37.9840, 23.7700, 900},
    {"athens", "Ιλίσια", "Ilisia", 37.9780, 23.7590, 800},
    {"athens", "Γκύζη", "Gyzi", 37.9930, 23.7510, 700},
    {"athens", "Πολύγωνο", "Polygono", 37.9960, 23.7560, 700},
    {"athens", "Πεδίον του Άρεως", "Pedion tou Areos", 37.9940, 23.7350, 500},
    {"athens", "Ομόνοια", "Omonoia", 37.9840, 23.7280, 500},
    {"athens", "Σύνταγμα", "Syntagma", 37.9755, 23.7348, 500},
    {"athens", "Μετς", "Mets", 37.9660, 23.7400, 500},
    {"athens", "Νέος Κόσμος", "Neos Kosmos", 37.9580, 23.7280, 900},
    {"athens", "Ζωγράφου", "Zografou", 37.9770, 23.7700, 1500},
    {"athens", "Καισαριανή", "Kaisariani", 37.9640, 23.7650, 1000},
    {"athens", "Βύρωνας", "Vyronas", 37.9600, 23.7530, 1300},
    {"athens", "Γαλάτσι", "Galatsi", 38.0180, 23.7550, 1500},
    {"athens", "Νέα Φιλαδέλφεια", "Nea Filadelfeia", 38.0350, 23.7380, 1300},
    {"athens", "Νέα Ιωνία", "Nea Ionia", 38.0400, 23.7550, 1500},
    {"athens", "Ηράκλειο Αττικής", "Irakleio Attikis", 38.0540, 23.7660, 1500},
    {"athens", "Μαρούσι", "Marousi", 38.0500, 23.8060, 2000},
    {"athens", "Χαλάνδρι", "Chalandri", 38.0210, 23.7980, 1800},
    {"athens", "Ψυχικό", "Psychiko", 38.0100, 23.7700, 1200},
    {"athens", "Νέο Ψυχικό", "Neo Psychiko", 38.0050, 23.7800, 900},
    {"athens", "Φιλοθέη", "Filothei", 38.0230, 23.7840, 1000},
    {"athens", "Κηφισιά", "Kifisia", 38.0740, 23.8110, 2000},
    {"athens", "Βριλήσσια", "Vrilissia", 38.0350, 23.8310, 1500},
    {"athens", "Αγία Παρασκευή", "Agia Paraskevi", 38.0110, 23.8200, 1800},
    {"athens", "Χολαργός", "Cholargos", 38.0040, 23.7980, 1300},
    {"athens", "Παπάγου", "Papagou", 37.9900, 23.7930, 1000},
    {"athens", "Γλυφάδα", "Glyfada", 37.8630, 23.7540, 2500},
    {"athens", "Βούλα", "Voula", 37.8440, 23.7720, 1800},
    {"athens", "Άλιμος", "Alimos", 37.9100, 23.7200, 1500},
    {"athens", "Παλαιό Φάληρο", "Palaio Faliro", 37.9280, 23.7000, 1800},
    {"athens", "Νέα Σμύρνη", "Nea Smyrni", 37.9450, 23.7140, 1500},
    {"athens", "Καλλιθέα", "Kallithea", 37.9550, 23.7020, 1800},
    {"athens", "Μοσχάτο", "Moschato", 37.9530, 23.6800, 1200},
    {"athens", "Άγιος Δημήτριος", "Agios Dimitrios", 37.9330, 23.7300, 1500},
    {"athens", "Ηλιούπολη", "Ilioupoli", 37.9310, 23.7570, 1800},
    {"athens", "Περιστέρι", "Peristeri", 38.0150, 23.6900, 2000},
    {"athens", "Αιγάλεω", "Egaleo", 37.9920, 23.6820, 1800},
    {"piraeus", "Καστέλλα", "Kastella", 37.9380, 23.6590, 800},
    {"piraeus", "Πασαλιμάνι", "Pasalimani", 37.9360, 23.6510, 600},
    {"thessaloniki", "Κέντρο", "Kentro", 40.6330, 22.9440, 1000},
    {"thessaloniki", "Λαδάδικα", "Ladadika", 40.6350, 22.9370, 400},
    {"thessaloniki", "Άνω Πόλη", "Ano Poli", 40.6430, 22.9580, 900},
    {"thessaloniki", "Καμάρα", "Kamara", 40.6320, 22.9520, 500},
    {"thessaloniki", "Ανάληψη", "Analipsi", 40.6150, 22.9580, 600},
    {"thessaloniki", "Μπότσαρη", "Botsari", 40.6070, 22.9620, 600},
    {"thessaloniki", "Τούμπα", "Toumba", 40.6110, 22.9700, 1300},
    {"thessaloniki", "Χαριλάου", "Charilaou", 40.6000, 22.9680, 1200},
    {"thessaloniki", "Ντεπώ", "Depo", 40.5930, 22.9620, 800},
    {"thessaloniki", "Καλαμαριά", "Kalamaria", 40.5820, 22.9500, 2000},
    {"thessaloniki", "Πυλαία", "Pylaia", 40.5970, 22.9890, 1500},
    {"thessaloniki", "Πανόραμα", "Panorama", 40.5880, 23.0310, 1500},
    {"thessaloniki", "Νεάπολη", "Neapoli", 40.6550, 22.9420, 1000},
    {"thessaloniki", "Συκιές", "Sykies", 40.6500, 22.9530, 1000},
    {"thessaloniki", "Σταυρούπολη", "Stavroupoli", 40.6680, 22.9350, 1300},
    {"thessaloniki", "Αμπελόκηποι Θεσσαλονίκης", "Ampelokipoi Thessalonikis", 40.6530, 22.9230,
     1000},
    {"thessaloniki", "Εύοσμος", "Evosmos", 40.6710, 22.9100, 1500},
    {"thessaloniki", "Πολίχνη", "Polichni", 40.6630, 22.9500, 1200},
    {"thessaloniki", "Περαία", "Peraia", 40.5000, 22.9250, 1500}
  ]

  def up do
    gazetteer()
    home_areas()
    social_and_filters()
    discovery_indexes()
    matchers()
    definers()
    replace_notification_types(@before_types ++ @around_types)
  end

  def down do
    replace_notification_types(@before_types)

    for function <- [
          "milos_around_alert_candidates",
          "milos_around_pins",
          "milos_around_counts",
          "milos_around_posts",
          "milos_around_clubs",
          "milos_around_boxes",
          "milos_around_events",
          "milos_around_match_posts",
          "milos_around_match_clubs",
          "milos_around_match_boxes",
          "milos_around_match_events",
          "milos_around_host_places",
          "milos_around_tags_match"
        ] do
      execute("DROP FUNCTION IF EXISTS #{function} CASCADE")
    end

    execute("DROP INDEX IF EXISTS community_events_open_point_index")
    execute("DROP INDEX IF EXISTS community_events_open_location_index")
    execute("DROP INDEX IF EXISTS community_posts_public_organization_index")
    execute("DROP INDEX IF EXISTS saved_filters_alerts_index")

    drop constraint(:saved_filters, :saved_filters_alert_check)

    alter table(:saved_filters) do
      remove :alert_enabled
      remove :alert_checked_on
      remove :alert_checked_at
    end

    alter table(:community_social_settings) do
      remove :visible_around
    end

    drop table(:user_home_areas)
    drop table(:places_neighbourhoods)
  end

  defp gazetteer do
    create table(:places_neighbourhoods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Stable natural key ("athens-kypseli"); never renamed.
      add :slug, :string, null: false
      add :kind, :string, null: false
      add :name, :string, null: false
      add :name_en, :string, null: false
      add :city_slug, :string
      add :country_code, :string, size: 2, null: false
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      # How far the place reaches from its centroid, roughly.
      add :radius_m, :integer, null: false
      # Lower case, accents dropped: name, English name and city.
      add :search_key, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:places_neighbourhoods, [:slug])

    create constraint(:places_neighbourhoods, :places_neighbourhoods_kind_check,
             check: "kind IN ('neighbourhood', 'city')"
           )

    create constraint(:places_neighbourhoods, :places_neighbourhoods_point_check,
             check:
               "latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180 AND radius_m BETWEEN 100 AND 50000"
           )

    execute("""
    CREATE INDEX places_neighbourhoods_point_index ON places_neighbourhoods
    USING gist (milos_geo_point(latitude, longitude))
    """)

    # Reference data: anyone reads it, nobody writes it outside migrations.
    execute("ALTER TABLE places_neighbourhoods ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE places_neighbourhoods FORCE ROW LEVEL SECURITY")

    execute(
      "CREATE POLICY places_neighbourhoods_read_policy ON places_neighbourhoods FOR SELECT USING (true)"
    )

    flush()
    seed_gazetteer()
  end

  defp seed_gazetteer do
    now = NaiveDateTime.utc_now()
    city_names = Map.new(@cities, fn {slug, name, en, _, _, _} -> {slug, {name, en}} end)

    cities =
      Enum.map(@cities, fn {slug, name, en, lat, lng, radius} ->
        place(slug, "city", name, en, nil, lat, lng, radius, [name, en], now)
      end)

    neighbourhoods =
      Enum.map(@neighbourhoods, fn {city, name, en, lat, lng, radius} ->
        {city_name, city_en} = Map.fetch!(city_names, city)

        place(
          "#{city}-#{slugify(en)}",
          "neighbourhood",
          name,
          en,
          city,
          lat,
          lng,
          radius,
          [name, en, city_name, city_en],
          now
        )
      end)

    repo().insert_all("places_neighbourhoods", cities ++ neighbourhoods)
  end

  defp place(slug, kind, name, en, city, lat, lng, radius, terms, now) do
    %{
      id: Ecto.UUID.bingenerate(),
      slug: slug,
      kind: kind,
      name: name,
      name_en: en,
      city_slug: city,
      country_code: "GR",
      latitude: lat,
      longitude: lng,
      radius_m: radius,
      search_key: terms |> Enum.map(&search_key/1) |> Enum.join(" "),
      inserted_at: now,
      updated_at: now
    }
  end

  # The same normalisation as Places.Domain.SearchKey (kept here so the
  # migration never depends on application code that may change).
  defp search_key(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace("ς", "σ")
  end

  defp slugify(text),
    do: text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

  defp home_areas do
    create table(:user_home_areas, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :neighbourhood_id,
          references(:places_neighbourhoods, type: :binary_id, on_delete: :delete_all),
          null: false

      # 0 is the main neighbourhood: where the person's public posts show.
      add :position, :smallint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_home_areas, [:user_id, :neighbourhood_id])
    create unique_index(:user_home_areas, [:user_id, :position])

    create constraint(:user_home_areas, :user_home_areas_position_check,
             check: "position BETWEEN 0 AND 4"
           )

    create index(:user_home_areas, [:neighbourhood_id, :user_id],
             where: "position = 0",
             name: :user_home_areas_main_index
           )

    owner = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY user_home_areas_owner_policy ON user_home_areas
    FOR ALL USING (#{owner}) WITH CHECK (#{owner})
    """)

    execute("ALTER TABLE user_home_areas ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE user_home_areas FORCE ROW LEVEL SECURITY")
  end

  defp social_and_filters do
    alter table(:community_social_settings) do
      add :visible_around, :boolean, null: false, default: false
    end

    alter table(:saved_filters) do
      add :alert_enabled, :boolean, null: false, default: false
      # The Athens day the alert last looked, and the instant it looked from:
      # only items created after `alert_checked_at` are new.
      add :alert_checked_on, :date
      add :alert_checked_at, :utc_datetime_usec
    end

    create constraint(:saved_filters, :saved_filters_alert_check,
             check: "NOT alert_enabled OR (kind = 'named' AND alert_checked_at IS NOT NULL)"
           )

    create index(:saved_filters, [:alert_checked_on],
             where: "alert_enabled",
             name: :saved_filters_alerts_index
           )
  end

  defp discovery_indexes do
    # Events with a place of their own (not one of the box's locations).
    execute("""
    CREATE INDEX community_events_open_point_index ON community_events
    USING gist (milos_geo_point(latitude, longitude))
    WHERE open_to_non_members AND cancelled_at IS NULL AND latitude IS NOT NULL
    """)

    # Events at one of the box's locations.
    execute("""
    CREATE INDEX community_events_open_location_index ON community_events (location_id, starts_at)
    WHERE open_to_non_members AND cancelled_at IS NULL AND location_id IS NOT NULL
    """)

    # A box's public posts, newest first.
    execute("""
    CREATE INDEX community_posts_public_organization_index
    ON community_posts (organization_id, inserted_at DESC)
    WHERE audience = 'public' AND deleted_at IS NULL AND hidden_at IS NULL
    """)
  end

  # Inlinable building blocks (LANGUAGE sql, no SECURITY DEFINER, no SET):
  # the planner folds them into the caller, so the spatial predicates reach
  # the GiST indexes. Called directly they run with the caller's rights.
  defp matchers do
    # A host's tags come from its published snapshot; an unpublished host
    # matches no tag filter. Within a list any tag matches, except amenities,
    # which must all be there.
    execute("""
    CREATE FUNCTION milos_around_tags_match(
      snapshot jsonb, disciplines text[], audiences text[], languages text[], amenities text[]
    )
    RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
      SELECT (disciplines IS NULL OR COALESCE(snapshot -> 'disciplines', '[]'::jsonb) ?| disciplines)
         AND (audiences IS NULL OR COALESCE(snapshot -> 'audiences', '[]'::jsonb) ?| audiences)
         AND (languages IS NULL OR COALESCE(snapshot -> 'languages', '[]'::jsonb) ?| languages)
         AND (amenities IS NULL OR COALESCE(snapshot -> 'amenities', '[]'::jsonb) ?& amenities)
    $$
    """)

    # Each active gym's nearest pinned location inside the search area.
    execute("""
    CREATE FUNCTION milos_around_host_places(origin geography, radius_m double precision, bbox geography)
    RETURNS TABLE (
      organization_id uuid, location_id uuid, latitude double precision,
      longitude double precision, neighbourhood text, city text, distance_m double precision
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT DISTINCT ON (l.organization_id)
             l.organization_id, l.id, l.latitude, l.longitude, l.neighbourhood::text, l.city::text,
             ST_Distance(milos_geo_point(l.latitude, l.longitude), origin)
      FROM public.facility_locations l
      JOIN public.organizations o ON o.id = l.organization_id AND o.status = 'active'
      WHERE l.latitude IS NOT NULL AND l.archived_at IS NULL
        AND milos_geo_point(l.latitude, l.longitude) && bbox
        AND ST_DWithin(milos_geo_point(l.latitude, l.longitude), origin, radius_m)
      ORDER BY l.organization_id, 7, l.id
    $$
    """)

    # Upcoming events open to everyone, at their own place, at one of the
    # box's locations, or (no place given) at the box's nearest location.
    execute("""
    CREATE FUNCTION milos_around_match_events(
      origin geography, radius_m double precision, bbox geography, now_at timestamptz,
      win_from timestamptz[], win_to timestamptz[], max_price_cents integer,
      disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz
    )
    RETURNS TABLE (
      id uuid, organization_id uuid, latitude double precision, longitude double precision,
      distance_m double precision, starts_at timestamptz, created_at timestamptz, title text
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT e.id, e.organization_id, placed.latitude, placed.longitude, placed.distance_m,
             e.starts_at, e.inserted_at, e.title::text
      FROM (
        SELECT pe.id, pe.latitude, pe.longitude,
               ST_Distance(milos_geo_point(pe.latitude, pe.longitude), origin) AS distance_m
        FROM public.community_events pe
        WHERE pe.open_to_non_members AND pe.cancelled_at IS NULL AND pe.latitude IS NOT NULL
          AND milos_geo_point(pe.latitude, pe.longitude) && bbox
          AND ST_DWithin(milos_geo_point(pe.latitude, pe.longitude), origin, radius_m)
          AND pe.starts_at >= now_at
        UNION ALL
        SELECT le.id, l.latitude, l.longitude,
               ST_Distance(milos_geo_point(l.latitude, l.longitude), origin)
        FROM public.facility_locations l
        JOIN public.community_events le
          ON le.location_id = l.id AND le.organization_id = l.organization_id
        WHERE l.latitude IS NOT NULL AND l.archived_at IS NULL
          AND milos_geo_point(l.latitude, l.longitude) && bbox
          AND ST_DWithin(milos_geo_point(l.latitude, l.longitude), origin, radius_m)
          AND le.open_to_non_members AND le.cancelled_at IS NULL AND le.location_id IS NOT NULL
          AND le.latitude IS NULL AND le.starts_at >= now_at
        UNION ALL
        SELECT he.id, h.latitude, h.longitude, h.distance_m
        FROM public.milos_around_host_places(origin, radius_m, bbox) h
        JOIN public.community_events he ON he.organization_id = h.organization_id
        WHERE he.open_to_non_members AND he.cancelled_at IS NULL
          AND he.latitude IS NULL AND he.location_id IS NULL AND he.starts_at >= now_at
      ) placed
      JOIN public.community_events e ON e.id = placed.id
      JOIN public.organizations o ON o.id = e.organization_id AND o.status = 'active'
      LEFT JOIN public.organization_public_profiles pr
        ON pr.organization_id = e.organization_id AND pr.published_at IS NOT NULL
      WHERE (win_from IS NULL OR EXISTS (
               SELECT 1 FROM unnest(win_from, win_to) AS w(f, t)
               WHERE e.starts_at >= w.f AND e.starts_at < w.t))
        AND (max_price_cents IS NULL OR e.price_cents <= max_price_cents)
        AND (created_after IS NULL OR e.inserted_at > created_after)
        AND milos_around_tags_match(pr.published_snapshot, disciplines, audiences, languages, amenities)
    $$
    """)

    # Gyms with a published page, at their nearest location.
    execute("""
    CREATE FUNCTION milos_around_match_boxes(
      origin geography, radius_m double precision, bbox geography,
      trial_only boolean, exclude_ids uuid[],
      disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz
    )
    RETURNS TABLE (
      organization_id uuid, location_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, neighbourhood text, city text,
      takes_trials boolean, snapshot jsonb, published_at timestamptz, slug text, title text,
      logo_url text, primary_color text
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT h.organization_id, h.location_id, h.latitude, h.longitude, h.distance_m,
             h.neighbourhood, h.city, COALESCE(t.enabled, false), pr.published_snapshot,
             pr.published_at, o.slug::text, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text
      FROM public.milos_around_host_places(origin, radius_m, bbox) h
      JOIN public.organizations o ON o.id = h.organization_id
      JOIN public.organization_public_profiles pr
        ON pr.organization_id = h.organization_id AND pr.published_at IS NOT NULL
      LEFT JOIN public.organization_settings s ON s.organization_id = h.organization_id
      LEFT JOIN public.scheduling_trial_policies t ON t.organization_id = h.organization_id
      WHERE (NOT trial_only OR COALESCE(t.enabled, false))
        AND (exclude_ids IS NULL OR NOT (h.organization_id = ANY (exclude_ids)))
        AND (created_after IS NULL OR pr.published_at > created_after)
        AND milos_around_tags_match(pr.published_snapshot, disciplines, audiences, languages, amenities)
    $$
    """)

    # Open clubs anyone signed in can join (at once or on request), at
    # their box's nearest location.
    execute("""
    CREATE FUNCTION milos_around_match_clubs(
      origin geography, radius_m double precision, bbox geography,
      disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz
    )
    RETURNS TABLE (
      id uuid, organization_id uuid, latitude double precision, longitude double precision,
      distance_m double precision, created_at timestamptz, title text
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT c.id, c.organization_id, h.latitude, h.longitude, h.distance_m, c.inserted_at,
             c.name::text
      FROM public.milos_around_host_places(origin, radius_m, bbox) h
      JOIN public.community_clubs c
        ON c.organization_id = h.organization_id AND c.kind = 'open' AND c.archived_at IS NULL
      LEFT JOIN public.organization_public_profiles pr
        ON pr.organization_id = h.organization_id AND pr.published_at IS NOT NULL
      WHERE c.join_policy IN ('open', 'approval')
        AND (created_after IS NULL OR c.inserted_at > created_after)
        AND milos_around_tags_match(pr.published_snapshot, disciplines, audiences, languages, amenities)
    $$
    """)

    # Public posts: by published boxes (at the box's nearest location) and by
    # people who opted in to «Φαίνομαι στο Γύρω μου» (at their main
    # neighbourhood's centroid, never more precise). A person's post carries
    # no tags, so any tag filter leaves it out.
    execute("""
    CREATE FUNCTION milos_around_match_posts(
      origin geography, radius_m double precision, bbox geography, since timestamptz,
      viewer_id uuid, disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz
    )
    RETURNS TABLE (
      id uuid, source text, organization_id uuid, author_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, created_at timestamptz,
      title text
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT p.id, 'club'::text, p.organization_id, p.author_id, h.latitude, h.longitude,
             h.distance_m, p.inserted_at, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text
      FROM public.milos_around_host_places(origin, radius_m, bbox) h
      JOIN public.organizations o ON o.id = h.organization_id
      JOIN public.organization_public_profiles pr
        ON pr.organization_id = h.organization_id AND pr.published_at IS NOT NULL
      LEFT JOIN public.organization_settings s ON s.organization_id = h.organization_id
      JOIN public.community_posts p
        ON p.organization_id = h.organization_id AND p.audience = 'public'
       AND p.deleted_at IS NULL AND p.hidden_at IS NULL
      WHERE p.inserted_at >= since
        AND (created_after IS NULL OR p.inserted_at > created_after)
        AND milos_around_tags_match(pr.published_snapshot, disciplines, audiences, languages, amenities)
        AND (viewer_id IS NULL OR NOT EXISTS (
               SELECT 1 FROM public.community_reports r
               WHERE r.target_type = 'post' AND r.target_id = p.id AND r.reporter_id = viewer_id))
      UNION ALL
      SELECT pp.id, 'profile'::text, NULL::uuid, pp.user_id, n.latitude, n.longitude,
             ST_Distance(milos_geo_point(n.latitude, n.longitude), origin), pp.inserted_at,
             u.nickname::text
      FROM public.places_neighbourhoods n
      JOIN public.user_home_areas a ON a.neighbourhood_id = n.id AND a.position = 0
      JOIN public.community_social_settings ss ON ss.user_id = a.user_id AND ss.visible_around
      JOIN public.users u ON u.id = a.user_id
      JOIN public.community_profile_posts pp
        ON pp.user_id = a.user_id AND pp.audience = 'public' AND pp.deleted_at IS NULL
      WHERE milos_geo_point(n.latitude, n.longitude) && bbox
        AND ST_DWithin(milos_geo_point(n.latitude, n.longitude), origin, radius_m)
        AND pp.inserted_at >= since
        AND (created_after IS NULL OR pp.inserted_at > created_after)
        AND disciplines IS NULL AND audiences IS NULL AND languages IS NULL AND amenities IS NULL
    $$
    """)
  end

  defp definers do
    definer = "LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp"

    # Each search: the page after the cursor, plus how many match in all.
    execute("""
    CREATE FUNCTION milos_around_events(
      origin geography, radius_m double precision, bbox geography, now_at timestamptz,
      win_from timestamptz[], win_to timestamptz[], max_price_cents integer,
      disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz, after_starts_at timestamptz, after_id uuid, lim integer
    )
    RETURNS TABLE (
      id uuid, organization_id uuid, latitude double precision, longitude double precision,
      distance_m double precision, starts_at timestamptz, total bigint
    )
    #{definer}
    AS $$
      SELECT m.id, m.organization_id, m.latitude, m.longitude, m.distance_m, m.starts_at, m.total
      FROM (
        SELECT x.*, count(*) OVER () AS total
        FROM milos_around_match_events(origin, radius_m, bbox, now_at, win_from, win_to,
               max_price_cents, disciplines, audiences, languages, amenities, created_after) x
      ) m
      WHERE after_id IS NULL OR (m.starts_at, m.id) > (after_starts_at, after_id)
      ORDER BY m.starts_at, m.id
      LIMIT lim
    $$
    """)

    # Gyms taking trials first, then nearest.
    execute("""
    CREATE FUNCTION milos_around_boxes(
      origin geography, radius_m double precision, bbox geography,
      trial_only boolean, exclude_ids uuid[],
      disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz, after_rank integer, after_distance double precision,
      after_id uuid, lim integer
    )
    RETURNS TABLE (
      organization_id uuid, location_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, neighbourhood text, city text,
      takes_trials boolean, snapshot jsonb, slug text, title text, logo_url text,
      primary_color text, rank integer, total bigint
    )
    #{definer}
    AS $$
      SELECT m.organization_id, m.location_id, m.latitude, m.longitude, m.distance_m,
             m.neighbourhood, m.city, m.takes_trials, m.snapshot, m.slug, m.title, m.logo_url,
             m.primary_color, m.rank, m.total
      FROM (
        SELECT x.*, CASE WHEN x.takes_trials THEN 0 ELSE 1 END AS rank,
               count(*) OVER () AS total
        FROM milos_around_match_boxes(origin, radius_m, bbox, trial_only, exclude_ids,
               disciplines, audiences, languages, amenities, created_after) x
      ) m
      WHERE after_id IS NULL
         OR (m.rank, m.distance_m, m.organization_id) > (after_rank, after_distance, after_id)
      ORDER BY m.rank, m.distance_m, m.organization_id
      LIMIT lim
    $$
    """)

    execute("""
    CREATE FUNCTION milos_around_clubs(
      origin geography, radius_m double precision, bbox geography,
      disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz, after_distance double precision, after_id uuid, lim integer
    )
    RETURNS TABLE (
      id uuid, organization_id uuid, latitude double precision, longitude double precision,
      distance_m double precision, total bigint
    )
    #{definer}
    AS $$
      SELECT m.id, m.organization_id, m.latitude, m.longitude, m.distance_m, m.total
      FROM (
        SELECT x.*, count(*) OVER () AS total
        FROM milos_around_match_clubs(origin, radius_m, bbox, disciplines, audiences,
               languages, amenities, created_after) x
      ) m
      WHERE after_id IS NULL OR (m.distance_m, m.id) > (after_distance, after_id)
      ORDER BY m.distance_m, m.id
      LIMIT lim
    $$
    """)

    # Newest first.
    execute("""
    CREATE FUNCTION milos_around_posts(
      origin geography, radius_m double precision, bbox geography, since timestamptz,
      viewer_id uuid, disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz, before_at timestamptz, before_id uuid, lim integer
    )
    RETURNS TABLE (
      id uuid, source text, organization_id uuid, author_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, created_at timestamptz,
      total bigint
    )
    #{definer}
    AS $$
      SELECT m.id, m.source, m.organization_id, m.author_id, m.latitude, m.longitude,
             m.distance_m, m.created_at, m.total
      FROM (
        SELECT x.*, count(*) OVER () AS total
        FROM milos_around_match_posts(origin, radius_m, bbox, since, viewer_id, disciplines,
               audiences, languages, amenities, created_after) x
      ) m
      WHERE before_id IS NULL OR (m.created_at, m.id) < (before_at, before_id)
      ORDER BY m.created_at DESC, m.id DESC
      LIMIT lim
    $$
    """)

    # How many match per kind within each radius, in one pass over the
    # largest radius (the «θέλεις πιο μακριά;» counts, and the alert counts).
    execute("""
    CREATE FUNCTION milos_around_counts(
      origin geography, radii double precision[], max_radius_m double precision,
      bbox geography, kinds text[], now_at timestamptz,
      win_from timestamptz[], win_to timestamptz[], max_price_cents integer,
      trial_only boolean, exclude_ids uuid[], since timestamptz, viewer_id uuid,
      disciplines text[], audiences text[], languages text[], amenities text[],
      created_after timestamptz
    )
    RETURNS TABLE (kind text, radius_m double precision, total bigint)
    #{definer}
    AS $$
      SELECT x.kind, r.radius_m, count(*) FILTER (WHERE x.distance_m <= r.radius_m)
      FROM (
        SELECT 'events'::text AS kind, e.distance_m
        FROM milos_around_match_events(origin, max_radius_m, bbox, now_at, win_from, win_to,
               max_price_cents, disciplines, audiences, languages, amenities, created_after) e
        WHERE 'events' = ANY (kinds)
        UNION ALL
        SELECT 'boxes', b.distance_m
        FROM milos_around_match_boxes(origin, max_radius_m, bbox, trial_only, exclude_ids,
               disciplines, audiences, languages, amenities, created_after) b
        WHERE 'boxes' = ANY (kinds)
        UNION ALL
        SELECT 'clubs', c.distance_m
        FROM milos_around_match_clubs(origin, max_radius_m, bbox, disciplines, audiences,
               languages, amenities, created_after) c
        WHERE 'clubs' = ANY (kinds)
        UNION ALL
        SELECT 'posts', p.distance_m
        FROM milos_around_match_posts(origin, max_radius_m, bbox, since, viewer_id,
               disciplines, audiences, languages, amenities, created_after) p
        WHERE 'posts' = ANY (kinds)
      ) x
      CROSS JOIN unnest(radii) AS r(radius_m)
      GROUP BY x.kind, r.radius_m
    $$
    """)

    # Map pins («Ψάξε εδώ»): every kind in one capped list, nearest first.
    execute("""
    CREATE FUNCTION milos_around_pins(
      origin geography, radius_m double precision, bbox geography, kinds text[],
      now_at timestamptz, win_from timestamptz[], win_to timestamptz[],
      max_price_cents integer, trial_only boolean, exclude_ids uuid[], since timestamptz,
      viewer_id uuid, disciplines text[], audiences text[], languages text[],
      amenities text[], lim integer
    )
    RETURNS TABLE (
      kind text, id uuid, latitude double precision, longitude double precision, title text,
      slug text, distance_m double precision
    )
    #{definer}
    AS $$
      SELECT x.kind, x.id, x.latitude, x.longitude, x.title, x.slug, x.distance_m
      FROM (
        SELECT 'events'::text AS kind, e.id, e.latitude, e.longitude, e.title,
               NULL::text AS slug, e.distance_m
        FROM milos_around_match_events(origin, radius_m, bbox, now_at, win_from, win_to,
               max_price_cents, disciplines, audiences, languages, amenities, NULL) e
        WHERE 'events' = ANY (kinds)
        UNION ALL
        SELECT 'boxes', b.organization_id, b.latitude, b.longitude, b.title, b.slug,
               b.distance_m
        FROM milos_around_match_boxes(origin, radius_m, bbox, trial_only, exclude_ids,
               disciplines, audiences, languages, amenities, NULL) b
        WHERE 'boxes' = ANY (kinds)
        UNION ALL
        SELECT 'clubs', c.id, c.latitude, c.longitude, c.title, NULL, c.distance_m
        FROM milos_around_match_clubs(origin, radius_m, bbox, disciplines, audiences,
               languages, amenities, NULL) c
        WHERE 'clubs' = ANY (kinds)
        UNION ALL
        SELECT 'posts', p.id, p.latitude, p.longitude, p.title, NULL, p.distance_m
        FROM milos_around_match_posts(origin, radius_m, bbox, since, viewer_id,
               disciplines, audiences, languages, amenities, NULL) p
        WHERE 'posts' = ANY (kinds)
      ) x
      ORDER BY x.distance_m, x.id
      LIMIT lim
    $$
    """)

    # The daily alert sweep reaches every person's alerting filters; it
    # learns only which ones are due, then works in each person's session.
    execute("""
    CREATE FUNCTION milos_around_alert_candidates(today date, lim integer)
    RETURNS TABLE (id uuid, user_id uuid)
    #{definer}
    AS $$
      SELECT f.id, f.user_id
      FROM saved_filters f
      WHERE f.alert_enabled AND f.surface = 'around_me' AND f.kind = 'named'
        AND (f.alert_checked_on IS NULL OR f.alert_checked_on < today)
      ORDER BY f.alert_checked_on NULLS FIRST, f.id
      LIMIT lim
    $$
    """)
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end
end
