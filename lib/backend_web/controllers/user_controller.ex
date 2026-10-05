defmodule BackendWeb.UserController do
  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias Backend.Accounts
  alias Backend.RateLimit
  alias BackendWeb.Auth
  alias BackendWeb.Plugs.RateLimit, as: Limit

  # Making a user costs a database row (and, for an account, a slow password hash), so each way of
  # making one is limited per address, and again across everybody. See Backend.RateLimit.
  plug Limit, [policy: :guest] when action == :create_guest
  plug Limit, [policy: :register] when action == :register
  plug Limit, [policy: :login] when action == :login

  # POST /api/users/guest
  def create_guest(conn, _params) do
    # one more limit, across everybody, so many addresses together can't flood the table either
    with :ok <- RateLimit.hit(:guest_all, :everyone) do
      do_create_guest(conn)
    else
      {:error, retry_ms} -> Limit.reject(conn, retry_ms)
    end
  end

  defp do_create_guest(conn) do
    {:ok, %{user_id: user_id}} = Accounts.create_guest_user()
    user = Accounts.get_user(user_id)

    conn
    |> put_status(:created)
    |> json(session(user))
  rescue
    _e ->
      error(conn, :server_error)
  end

  # POST /api/users/register   body: {"username": "...", "email": "...", "password": "..."}
  def register(
        conn,
        %{"username" => _username, "email" => _email, "password" => _password} = params
      ) do
    with :ok <- RateLimit.hit(:register_all, :everyone) do
      case Accounts.register_user(params) do
        {:ok, user} ->
          conn
          |> put_status(:created)
          |> json(session(user))

        {:error, changeset} ->
          error(conn, changeset_errors(changeset))
      end
    else
      {:error, retry_ms} -> Limit.reject(conn, retry_ms)
    end
  end

  def register(conn, _params), do: error(conn, :invalid_params)

  # POST /api/users/login   body: {"username": "...", "password": "..."}
  def login(conn, %{"username" => username, "password" => password})
      when is_binary(username) and is_binary(password) do
    # per account as well as per address: guessing one person's password from many addresses
    # is slow too. (Names are compared without regard to case, like the lookup does.)
    with :ok <- RateLimit.hit(:login_user, String.downcase(username)) do
      case Accounts.verify_login(username, password) do
        {:ok, user} ->
          conn
          |> put_status(:ok)
          |> json(session(user))

        {:error, :invalid_credentials} ->
          error(conn, :invalid_credentials)
      end
    else
      {:error, retry_ms} -> Limit.reject(conn, retry_ms)
    end
  end

  def login(conn, _params), do: error(conn, :invalid_params)

  # GET /api/users/me   header: Authorization: Bearer <token>
  # The browser calls this on load to ask "is my saved login still valid, and who am I?"
  def me(conn, _params) do
    case conn.assigns.current_user do
      nil -> error(conn, :unauthorized)
      user -> json(conn, Map.delete(session(user), :token))
    end
  end

  defp session(user) do
    %{
      user_id: user.id,
      user_type: user.user_type,
      username: user.username,
      token: Auth.sign(user)
    }
  end

  defp error(conn, reason) do
    {status, message} =
      case reason do
        :invalid_credentials -> {401, "Username or password is incorrect"}
        :unauthorized -> {401, "Please log in again"}
        :invalid_params -> {422, "Missing required fields"}
        :server_error -> {500, "Could not create user, please try again"}
        errors when is_map(errors) -> {422, format_errors(errors)}
        _other -> {500, "Something went wrong"}
      end

    conn
    |> put_status(status)
    |> json(%{error: message})
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp format_errors(errors) when is_map(errors) do
    errors
    |> Enum.map(fn {field, messages} ->
      "#{field}: " <> Enum.join(List.wrap(messages), ", ")
    end)
    |> Enum.join("; ")
  end
end
