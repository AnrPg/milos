defmodule MilosTraining.Organizations.SchemasTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.{
    Organization,
    OrganizationDomain,
    OrganizationMembership,
    OrganizationSetting,
    RegistrationInvitation
  }

  @organization_id "b7c63d17-2039-4dd5-bf9d-e2f5845cde8d"
  @user_id "9d60a0ec-e742-4738-a12b-3eccf04ef60f"
  @now ~U[2026-07-18 10:00:00.000000Z]

  test "organization changeset derives a normalized slug from its name" do
    changeset = Organization.changeset(%{name: "  Mýlos Strength Club  "})

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :name) == "Mýlos Strength Club"
    assert Ecto.Changeset.get_change(changeset, :slug) == "mylos-strength-club"
    assert Ecto.Changeset.get_field(changeset, :status) == :active
  end

  test "organization changeset rejects malformed explicit slugs" do
    changeset = Organization.changeset(%{name: "Acme", slug: "-acme--gym"})

    refute changeset.valid?
    assert {"must be a 3-63 character URL-safe slug", _} = changeset.errors[:slug]
  end

  test "membership changeset enforces tenant role and lifecycle values" do
    valid =
      OrganizationMembership.changeset(%{
        organization_id: @organization_id,
        user_id: @user_id,
        role: :owner,
        status: :active,
        joined_at: @now
      })

    assert valid.valid?

    invalid =
      OrganizationMembership.changeset(%{
        organization_id: @organization_id,
        user_id: @user_id,
        role: :platform_admin,
        status: :active
      })

    refute invalid.valid?
  end

  test "invitation changeset accepts only digests and future bounded expiry" do
    valid =
      RegistrationInvitation.issue_changeset(
        %{
          organization_id: @organization_id,
          token_digest: :crypto.hash(:sha256, "one-time-token"),
          role: :member,
          expires_at: DateTime.add(@now, 3_600, :second)
        },
        @now
      )

    assert valid.valid?

    plaintext =
      RegistrationInvitation.issue_changeset(
        %{
          organization_id: @organization_id,
          token_digest: "one-time-token",
          role: :member,
          expires_at: DateTime.add(@now, 3_600, :second)
        },
        @now
      )

    refute plaintext.valid?

    expired =
      RegistrationInvitation.issue_changeset(
        %{
          organization_id: @organization_id,
          token_digest: :crypto.hash(:sha256, "expired-token"),
          role: :member,
          expires_at: @now
        },
        @now
      )

    refute expired.valid?
  end

  test "domain changeset canonicalizes a bare hostname and rejects URLs" do
    valid =
      OrganizationDomain.changeset(%{
        organization_id: @organization_id,
        host: " Gym.Example.COM. ",
        primary: true
      })

    assert valid.valid?
    assert Ecto.Changeset.get_change(valid, :host) == "gym.example.com"

    invalid =
      OrganizationDomain.changeset(%{
        organization_id: @organization_id,
        host: "https://gym.example.com"
      })

    refute invalid.valid?
  end

  test "settings changeset keeps invitation lifetimes within the platform maximum" do
    valid =
      OrganizationSetting.changeset(%{
        organization_id: @organization_id,
        timezone: "Europe/Athens",
        default_locale: "en",
        invitation_lifetime_seconds: 86_400
      })

    assert valid.valid?

    invalid =
      OrganizationSetting.changeset(%{
        organization_id: @organization_id,
        timezone: "Europe/Athens",
        default_locale: "en",
        invitation_lifetime_seconds: 604_801
      })

    refute invalid.valid?
  end
end
