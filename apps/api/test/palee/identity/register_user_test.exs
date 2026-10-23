defmodule Palee.Identity.RegisterUserTest do
  use Palee.DataCase, async: true

  alias Palee.Identity.Commands.RegisterUser

  describe "call/1" do
    test "creates user with valid params" do
      params = %{
        nickname: "atlas",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "atlas@placeholder.invalid"
      }

      assert {:ok, user} = RegisterUser.call(params)
      assert user.nickname == "atlas"
      assert user.role == :member
      refute user.password_hash == "S3cur3P@ss!42"
    end

    test "rejects a duplicate handle" do
      params = %{
        nickname: "atlas",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "atlas@placeholder.invalid"
      }

      {:ok, _user} = RegisterUser.call(params)

      assert {:error, changeset} =
               RegisterUser.call(%{params | email: "atlas-other@placeholder.invalid"})

      assert "has already been taken" in errors_on(changeset).handle
    end

    test "a second login with the same email is refused (ADR-187)" do
      params = %{
        nickname: "atlas",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "atlas@placeholder.invalid"
      }

      {:ok, _user} = RegisterUser.call(params)

      assert {:error, :email_taken} =
               RegisterUser.call(%{
                 params
                 | nickname: "atlas_two",
                   email: "ATLAS@placeholder.invalid"
               })
    end

    test "preserves a display nickname while normalizing it before uniqueness checks" do
      {:ok, user} =
        RegisterUser.call(%{
          nickname: "Atlas",
          password: "S3cur3P@ss!42",
          role: :member,
          email: "atlas2@placeholder.invalid"
        })

      assert user.nickname == "Atlas"
      assert user.handle == "atlas"
      assert user.normalized_nickname == "atlas"

      assert {:error, changeset} =
               RegisterUser.call(%{
                 nickname: "ATLAS",
                 password: "S3cur3P@ss!42",
                 role: :member,
                 email: "atlas3@placeholder.invalid"
               })

      assert "has already been taken" in errors_on(changeset).handle
    end

    test "rejects invalid role" do
      params = %{
        nickname: "atlas",
        password: "S3cur3P@ss!42",
        role: :admin,
        email: "atlas4@placeholder.invalid"
      }

      assert {:error, changeset} = RegisterUser.call(params)
      assert "is invalid" in errors_on(changeset).role
    end

    test "rejects passwords shorter than four characters" do
      params = %{
        nickname: "atlas",
        password: "123",
        role: :member,
        email: "atlas5@placeholder.invalid"
      }

      assert {:error, changeset} = RegisterUser.call(params)
      assert errors_on(changeset).password != []
    end

    test "accepts simple and whitespace-containing passwords with at least four characters" do
      params = %{
        nickname: "simple_pass",
        password: "a b ",
        role: :member,
        email: "simple-pass@placeholder.invalid"
      }

      assert {:ok, user} = RegisterUser.call(params)
      refute user.password_hash == "a b "
    end

    test "database rejects invalid roles outside Ecto changesets" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      assert_raise Postgrex.Error, fn ->
        Ecto.Adapters.SQL.query!(
          Repo,
          """
          INSERT INTO users (id, nickname, display_nickname, role, leaderboard_opt_in, login_id, inserted_at, updated_at)
          VALUES ($1, $2, $2, $3, $4, $5, $6, $7)
          """,
          [
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            "raw_insert_user",
            "owner",
            false,
            Ecto.UUID.dump!(raw_login_id(now)),
            now,
            now
          ]
        )
      end
    end
  end

  defp raw_login_id(now) do
    id = Ecto.UUID.generate()

    Ecto.Adapters.SQL.query!(
      Repo,
      "INSERT INTO logins (id, email, password_hash, inserted_at, updated_at) VALUES ($1, $2, 'h', $3, $3)",
      [Ecto.UUID.dump!(id), "raw-#{System.unique_integer([:positive])}@placeholder.invalid", now]
    )

    id
  end
end
