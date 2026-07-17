defmodule MilosTraining.Identity.RegisterUserTest do
  use MilosTraining.DataCase, async: true

  alias MilosTraining.Identity.Commands.RegisterUser

  describe "call/1" do
    test "creates user with valid params" do
      params = %{nickname: "atlas", password: "S3cur3P@ss!", role: :member}

      assert {:ok, user} = RegisterUser.call(params)
      assert user.nickname == "atlas"
      assert user.role == :member
      refute user.password_hash == "S3cur3P@ss!"
    end

    test "rejects duplicate nickname" do
      params = %{nickname: "atlas", password: "S3cur3P@ss!", role: :member}

      {:ok, _user} = RegisterUser.call(params)

      assert {:error, changeset} = RegisterUser.call(params)
      assert "has already been taken" in errors_on(changeset).nickname
    end

    test "preserves a display nickname while normalizing it before uniqueness checks" do
      {:ok, user} =
        RegisterUser.call(%{nickname: "Atlas", password: "S3cur3P@ss!", role: :member})

      assert user.nickname == "Atlas"
      assert user.normalized_nickname == "atlas"

      assert {:error, changeset} =
               RegisterUser.call(%{
                 nickname: "ATLAS",
                 password: "S3cur3P@ss!",
                 role: :member
               })

      assert "has already been taken" in errors_on(changeset).nickname
    end

    test "rejects invalid role" do
      params = %{nickname: "atlas", password: "S3cur3P@ss!", role: :admin}

      assert {:error, changeset} = RegisterUser.call(params)
      assert "is invalid" in errors_on(changeset).role
    end

    test "rejects weak password" do
      params = %{nickname: "atlas", password: "123", role: :member}

      assert {:error, changeset} = RegisterUser.call(params)
      assert errors_on(changeset).password != []
    end

    test "database rejects invalid roles outside Ecto changesets" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      assert_raise Postgrex.Error, fn ->
        Ecto.Adapters.SQL.query!(
          Repo,
          """
          INSERT INTO users (id, nickname, password_hash, role, leaderboard_opt_in, inserted_at, updated_at)
          VALUES ($1, $2, $3, $4, $5, $6, $7)
          """,
          [
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            "raw_insert_user",
            "hashed",
            "owner",
            false,
            now,
            now
          ]
        )
      end
    end
  end
end
