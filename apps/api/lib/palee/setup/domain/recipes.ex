defmodule Palee.Setup.Domain.Recipes do
  @moduledoc """
  The setup recipes a new business picks from (CP-H2, ADR-255): one per kind
  of box. Each is a starting point; everything it sets can be changed later
  in its own home. Prices are suggestions in the business's currency (whole
  cents) for the owner to adjust.

  Bump a recipe's `version` when its content changes: applications record
  the version they applied.
  """

  alias Palee.Setup.Domain.Recipe

  @week %{"period" => "calendar_week"}
  @validity %{"period" => "subscription_period"}

  @health_certificate %{
    key: "health_certificate",
    names: %{"en" => "Health certificate", "el" => "Βεβαίωση υγείας"}
  }

  @participation_terms %{
    key: "participation_terms",
    names: %{"en" => "Participation terms", "el" => "Όροι συμμετοχής"}
  }

  @trial_package %{
    code: "setup_trial",
    names: %{"en" => "Trial", "el" => "Δοκιμαστικό"},
    package_type: "trial",
    billing_period: "one_off",
    base_price_cents: 0,
    fields: %{}
  }

  @drop_in %{
    code: "setup_drop_in",
    names: %{"en" => "Drop-in", "el" => "Μία επίσκεψη"},
    package_type: "drop_in",
    billing_period: "one_off",
    base_price_cents: 1_500,
    fields: %{}
  }

  @front_desk_billing %{"front_desk" => ["manage_billing"]}

  @recipes [
    %Recipe{
      key: "crossfit_box",
      version: 1,
      names: %{"en" => "CrossFit box", "el" => "CrossFit box"},
      summaries: %{
        "en" =>
          "Daily WOD classes with automatic confirmation, a leaderboard, open gym and a free trial.",
        "el" =>
          "Τμήματα με WOD κάθε μέρα, αυτόματη επιβεβαίωση κρατήσεων, κατάταξη, ελεύθερη προπόνηση και δωρεάν δοκιμαστικό."
      },
      settings: %{
        "scheduling.default_capacity" => 16,
        "scheduling.default_auto_approve" => true,
        "scheduling.default_cancellation_cutoff_minutes" => 120,
        "scheduling.default_booking_window_days" => 7,
        "gamification.leaderboard_enabled" => true,
        "workouts.wod_assistant_enabled" => true,
        "finance.package_modules" => ["group_classes", "online_coaching", "open_gym"],
        "check_in.open_gym_requires_package" => true,
        "trials.enabled" => true,
        "trials.seats_per_class" => 2,
        "trials.approval" => "auto",
        "trials.conversion_package_id" => "setup_unlimited"
      },
      class_types: [
        %{slug: "wod", names: %{"en" => "WOD", "el" => "WOD"}},
        %{
          slug: "foundations",
          names: %{"en" => "Foundations", "el" => "Βασικές κινήσεις"},
          level: "beginner"
        },
        %{slug: "weightlifting", names: %{"en" => "Weightlifting", "el" => "Άρση βαρών"}},
        %{slug: "open-gym", names: %{"en" => "Open gym", "el" => "Ελεύθερη προπόνηση"}}
      ],
      packages: [
        %{
          code: "setup_unlimited",
          names: %{"en" => "Unlimited monthly", "el" => "Απεριόριστο μηνιαίο"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 8_000,
          fields: %{"facility.open_gym" => true}
        },
        %{
          code: "setup_three_a_week",
          names: %{"en" => "3 classes a week", "el" => "3 φορές την εβδομάδα"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 6_500,
          fields: %{"group_classes.visits" => Map.put(@week, "limit", 3)}
        },
        %{
          code: "setup_ten_classes",
          names: %{"en" => "10 classes", "el" => "10 επισκέψεις"},
          package_type: "class_pack",
          billing_period: "one_off",
          base_price_cents: 9_000,
          fields: %{}
        },
        @drop_in,
        @trial_package
      ],
      role_grants: @front_desk_billing,
      documents: [@health_certificate, @participation_terms]
    },
    %Recipe{
      key: "functional_hyrox",
      version: 1,
      names: %{"en" => "Functional / HYROX", "el" => "Functional / HYROX"},
      summaries: %{
        "en" => "Functional and HYROX classes, a leaderboard and a free trial.",
        "el" => "Τμήματα functional και HYROX, κατάταξη και δωρεάν δοκιμαστικό."
      },
      settings: %{
        "scheduling.default_capacity" => 14,
        "scheduling.default_auto_approve" => true,
        "scheduling.default_cancellation_cutoff_minutes" => 120,
        "scheduling.default_booking_window_days" => 7,
        "gamification.leaderboard_enabled" => true,
        "workouts.wod_assistant_enabled" => true,
        "finance.package_modules" => ["group_classes", "online_coaching"],
        "trials.enabled" => true,
        "trials.seats_per_class" => 2,
        "trials.approval" => "auto",
        "trials.conversion_package_id" => "setup_unlimited"
      },
      class_types: [
        %{slug: "functional", names: %{"en" => "Functional", "el" => "Functional"}},
        %{slug: "hyrox", names: %{"en" => "HYROX", "el" => "HYROX"}},
        %{slug: "strength", names: %{"en" => "Strength", "el" => "Δύναμη"}}
      ],
      packages: [
        %{
          code: "setup_unlimited",
          names: %{"en" => "Unlimited monthly", "el" => "Απεριόριστο μηνιαίο"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 7_000,
          fields: %{}
        },
        %{
          code: "setup_ten_classes",
          names: %{"en" => "10 classes", "el" => "10 επισκέψεις"},
          package_type: "class_pack",
          billing_period: "one_off",
          base_price_cents: 8_000,
          fields: %{}
        },
        @drop_in,
        @trial_package
      ],
      role_grants: @front_desk_billing,
      documents: [@health_certificate, @participation_terms]
    },
    %Recipe{
      key: "personal_training_studio",
      version: 1,
      names: %{"en" => "Personal training studio", "el" => "Στούντιο προσωπικής προπόνησης"},
      summaries: %{
        "en" =>
          "Personal training and small groups: staff confirm bookings, cancellations close 12 hours before, no leaderboard.",
        "el" =>
          "Προσωπική προπόνηση και μικρά τμήματα: το προσωπικό επιβεβαιώνει τις κρατήσεις, καθυστερημένη ακύρωση 12 ώρες πριν, χωρίς κατάταξη."
      },
      settings: %{
        "scheduling.default_capacity" => 4,
        "scheduling.default_auto_approve" => false,
        "scheduling.default_booking_timeout_minutes" => 240,
        "scheduling.default_cancellation_cutoff_minutes" => 720,
        "scheduling.default_booking_window_days" => 14,
        "gamification.leaderboard_enabled" => false,
        "finance.package_modules" => ["group_classes", "online_coaching", "personal_training"],
        "community.partners_enabled" => false,
        "trials.enabled" => true,
        "trials.seats_per_class" => 1,
        "trials.approval" => "manual"
      },
      class_types: [
        %{
          slug: "small-group",
          names: %{"en" => "Small group training", "el" => "Προπόνηση σε μικρή ομάδα"}
        }
      ],
      packages: [
        %{
          code: "setup_personal_training_10",
          names: %{
            "en" => "10 personal training sessions",
            "el" => "10 προσωπικές προπονήσεις"
          },
          package_type: "pt_pack",
          billing_period: "one_off",
          base_price_cents: 35_000,
          fields: %{}
        },
        %{
          code: "setup_small_group",
          names: %{"en" => "Small group, 2 a week", "el" => "Μικρή ομάδα, 2 φορές την εβδομάδα"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 9_000,
          fields: %{"group_classes.visits" => Map.put(@week, "limit", 2)}
        },
        @trial_package
      ],
      role_grants: %{},
      documents: [@health_certificate, @participation_terms]
    },
    %Recipe{
      key: "yoga_pilates_studio",
      version: 1,
      names: %{"en" => "Yoga / Pilates studio", "el" => "Στούντιο yoga / pilates"},
      summaries: %{
        "en" =>
          "Calm classes with automatic confirmation, cancellations close 4 hours before, no leaderboard and no WOD assistant.",
        "el" =>
          "Τμήματα με αυτόματη επιβεβαίωση κρατήσεων, καθυστερημένη ακύρωση 4 ώρες πριν, χωρίς κατάταξη και χωρίς βοηθό WOD."
      },
      settings: %{
        "scheduling.default_capacity" => 12,
        "scheduling.default_auto_approve" => true,
        "scheduling.default_cancellation_cutoff_minutes" => 240,
        "scheduling.default_booking_window_days" => 14,
        "gamification.leaderboard_enabled" => false,
        "gamification.streak_shields" => 2,
        "workouts.wod_assistant_enabled" => false,
        "finance.package_modules" => ["group_classes", "online_coaching"],
        "trials.enabled" => true,
        "trials.seats_per_class" => 2,
        "trials.approval" => "auto",
        "trials.conversion_package_id" => "setup_eight_a_month"
      },
      class_types: [
        %{slug: "yoga", names: %{"en" => "Yoga", "el" => "Yoga"}},
        %{slug: "pilates-mat", names: %{"en" => "Mat pilates", "el" => "Pilates στο στρώμα"}},
        %{slug: "pilates-reformer", names: %{"en" => "Reformer pilates", "el" => "Pilates reformer"}}
      ],
      packages: [
        %{
          code: "setup_eight_a_month",
          names: %{"en" => "8 classes a month", "el" => "8 τμήματα τον μήνα"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 6_000,
          fields: %{"group_classes.visits" => %{"limit" => 8, "period" => "calendar_month"}}
        },
        %{
          code: "setup_ten_classes",
          names: %{"en" => "10 classes", "el" => "10 επισκέψεις"},
          package_type: "class_pack",
          billing_period: "one_off",
          base_price_cents: 8_500,
          fields: %{}
        },
        @drop_in,
        @trial_package
      ],
      role_grants: %{},
      documents: [@health_certificate, @participation_terms]
    },
    %Recipe{
      key: "martial_arts_school",
      version: 1,
      names: %{"en" => "Martial arts school", "el" => "Σχολή πολεμικών τεχνών"},
      summaries: %{
        "en" =>
          "Adult and kids classes with automatic confirmation, bookings open two weeks ahead, no leaderboard.",
        "el" =>
          "Τμήματα ενηλίκων και παιδιών με αυτόματη επιβεβαίωση κρατήσεων, άνοιγμα κρατήσεων δύο εβδομάδες πριν, χωρίς κατάταξη."
      },
      settings: %{
        "scheduling.default_capacity" => 20,
        "scheduling.default_auto_approve" => true,
        "scheduling.default_booking_window_days" => 14,
        "gamification.leaderboard_enabled" => false,
        "workouts.wod_assistant_enabled" => false,
        "finance.package_modules" => ["group_classes", "events"],
        "trials.enabled" => true,
        "trials.seats_per_class" => 3,
        "trials.approval" => "auto",
        "trials.conversion_package_id" => "setup_unlimited"
      },
      class_types: [
        %{slug: "adults", names: %{"en" => "Adults", "el" => "Ενήλικες"}},
        %{
          slug: "kids",
          names: %{"en" => "Kids", "el" => "Παιδιά"},
          audiences: ["kids"]
        },
        %{slug: "open-mat", names: %{"en" => "Open mat", "el" => "Ελεύθερη εξάσκηση"}}
      ],
      packages: [
        %{
          code: "setup_unlimited",
          names: %{"en" => "Unlimited monthly", "el" => "Απεριόριστο μηνιαίο"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 6_000,
          fields: %{}
        },
        %{
          code: "setup_kids_monthly",
          names: %{"en" => "Kids, 2 a week", "el" => "Παιδιά, 2 φορές την εβδομάδα"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 4_500,
          fields: %{"group_classes.visits" => Map.put(@week, "limit", 2)}
        },
        @trial_package
      ],
      role_grants: %{},
      documents: [@health_certificate, @participation_terms]
    },
    %Recipe{
      key: "open_gym",
      version: 1,
      names: %{"en" => "Open gym", "el" => "Γυμναστήριο ελεύθερης προπόνησης"},
      summaries: %{
        "en" =>
          "Free training with a package at the door, a few group classes, the front desk can check people in by hand.",
        "el" =>
          "Ελεύθερη προπόνηση με πακέτο συνδρομής, λίγα τμήματα, η υποδοχή μπορεί να κάνει check-in χειροκίνητα."
      },
      settings: %{
        "scheduling.default_capacity" => 25,
        "scheduling.default_auto_approve" => true,
        "gamification.leaderboard_enabled" => false,
        "workouts.wod_assistant_enabled" => false,
        "finance.package_modules" => ["group_classes", "open_gym"],
        "check_in.open_gym_requires_package" => true,
        "check_in.desk_override" => true,
        "trials.enabled" => true,
        "trials.seats_per_class" => 3,
        "trials.approval" => "auto",
        "trials.conversion_package_id" => "setup_open_gym_monthly"
      },
      class_types: [
        %{slug: "group-class", names: %{"en" => "Group class", "el" => "Ομαδικό τμήμα"}}
      ],
      packages: [
        %{
          code: "setup_open_gym_monthly",
          names: %{"en" => "Open gym monthly", "el" => "Ελεύθερη προπόνηση μηνιαίο"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 4_000,
          fields: %{"facility.open_gym" => true}
        },
        %{
          code: "setup_open_gym_annual",
          names: %{"en" => "Open gym yearly", "el" => "Ελεύθερη προπόνηση ετήσιο"},
          package_type: "membership",
          billing_period: "annual",
          base_price_cents: 40_000,
          fields: %{"facility.open_gym" => true}
        },
        @drop_in,
        @trial_package
      ],
      role_grants: %{"front_desk" => ["manage_billing", "manage_shop"]},
      documents: [@health_certificate, @participation_terms]
    },
    %Recipe{
      key: "independent_coach",
      version: 1,
      names: %{"en" => "Independent coach", "el" => "Ανεξάρτητος coach"},
      summaries: %{
        "en" =>
          "Online programming and personal training for your own clients, without a box timetable.",
        "el" =>
          "Online προγραμματισμός και προσωπική προπόνηση για τους δικούς σου πελάτες, χωρίς πρόγραμμα box."
      },
      provider_kind: "coach",
      settings: %{
        "scheduling.default_capacity" => 6,
        "scheduling.default_auto_approve" => false,
        "scheduling.default_cancellation_cutoff_minutes" => 720,
        "gamification.leaderboard_enabled" => false,
        "finance.package_modules" => ["online_coaching", "personal_training"],
        "community.partners_enabled" => false,
        "trials.enabled" => false
      },
      class_types: [],
      packages: [
        %{
          code: "setup_online_programming",
          names: %{"en" => "Online programming monthly", "el" => "Online προγραμματισμός μηνιαίο"},
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 6_000,
          fields: %{
            "group_classes.included" => false,
            "online_coaching.included" => true
          }
        },
        %{
          code: "setup_personal_training_8",
          names: %{"en" => "8 personal training sessions", "el" => "8 προσωπικές προπονήσεις"},
          package_type: "pt_pack",
          billing_period: "one_off",
          base_price_cents: 28_000,
          fields: %{"personal_training.sessions" => Map.put(@validity, "limit", 8)}
        }
      ],
      role_grants: %{},
      documents: [@health_certificate]
    }
  ]

  @by_key Map.new(@recipes, &{&1.key, &1})

  @doc "Every recipe, in the order the owner sees them."
  def all, do: @recipes

  def keys, do: Enum.map(@recipes, & &1.key)

  def fetch(key) when is_binary(key) do
    case Map.fetch(@by_key, key) do
      {:ok, recipe} -> {:ok, recipe}
      :error -> {:error, :recipe_not_found}
    end
  end

  def fetch(_key), do: {:error, :recipe_not_found}
end
