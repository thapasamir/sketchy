defmodule Backend.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string
      add :email, :string
      add :password_hash, :string
      add :user_type, :string, null: false, default: "guest"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username], where: "user_type = 'registered'")
    create unique_index(:users, [:email], where: "user_type = 'registered'")
  end
end
