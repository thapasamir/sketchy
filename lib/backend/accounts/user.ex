defmodule Backend.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :user_type, :string, default: "guest"
    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password])
    |> validate_required([:user_type])
    |> validate_type()
  end

  def guest_changeset(attrs) do
    %__MODULE__{user_type: "guest"}
    |> cast(attrs, [])
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password])
    |> validate_required([:username, :email, :password])
    |> validate_length(:username, min: 3, max: 20)
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password, min: 6)
    |> unique_constraint(:username, name: :users_username_index)
    |> unique_constraint(:email, name: :users_email_index)
    |> hash_password()
  end

  def login_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:username, :password])
    |> validate_required([:username, :password])
  end

  defp hash_password(%Ecto.Changeset{changes: %{password: password}} = changeset) do
    put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
  end

  defp hash_password(changeset), do: changeset

  defp validate_type(changeset) do
    user_type = get_field(changeset, :user_type)

    if user_type in ["guest", "registered"] do
      changeset
    else
      add_error(changeset, :user_type, "invalid")
    end
  end
end
