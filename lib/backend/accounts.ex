defmodule Backend.Accounts do
  @moduledoc """
  The accounts domain. Handles user creation (guests and registered), login, and lookups.
  """

  import Ecto.Query

  alias Backend.Repo
  alias Backend.Accounts.User

  @doc "Create a temporary guest user. Returns `{:ok, %{user_id: id}}`."
  def create_guest_user do
    {:ok, user} =
      %User{user_type: "guest"}
      |> Repo.insert()

    {:ok, %{user_id: user.id}}
  end

  @doc "Register a new user. Returns `{:ok, user}` or `{:error, changeset}`."
  def register_user(attrs) do
    %User{user_type: "registered"}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Find a user by ID."
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Verify a login. Returns `{:ok, user}` if username and password match, `{:error, reason}` otherwise.
  """
  def verify_login(username, password) do
    user = Repo.one(from u in User, where: u.username == ^username)

    case user do
      nil ->
        # Do the same slow work as for a real account, so the time taken doesn't tell a caller
        # which usernames exist.
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        if Argon2.verify_pass(password, user.password_hash) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end
    end
  end
end
