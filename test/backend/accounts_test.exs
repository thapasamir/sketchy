defmodule Backend.AccountsTest do
  use Backend.DataCase, async: true

  alias Backend.Accounts

  @valid %{"username" => "samir", "email" => "s@example.com", "password" => "secret123"}

  test "guests are created without credentials" do
    assert {:ok, %{user_id: id}} = Accounts.create_guest_user()
    assert %{user_type: "guest", username: nil, password_hash: nil} = Accounts.get_user(id)
  end

  test "register stores a hash, never the password" do
    assert {:ok, user} = Accounts.register_user(@valid)
    assert user.user_type == "registered"
    assert user.password_hash != "secret123"
    assert String.starts_with?(user.password_hash, "$argon2")
  end

  test "register validates input" do
    assert {:error, cs} = Accounts.register_user(%{@valid | "password" => "123"})
    assert "should be at least 6 character(s)" in errors_on(cs).password

    assert {:error, cs} = Accounts.register_user(%{@valid | "email" => "nope"})
    assert errors_on(cs).email != []
  end

  test "username and email must be unique" do
    {:ok, _} = Accounts.register_user(@valid)
    assert {:error, cs} = Accounts.register_user(%{@valid | "email" => "other@example.com"})
    assert errors_on(cs).username != []
    assert {:error, cs} = Accounts.register_user(%{@valid | "username" => "other"})
    assert errors_on(cs).email != []
  end

  test "login accepts the right password only" do
    {:ok, user} = Accounts.register_user(@valid)
    assert {:ok, found} = Accounts.verify_login("samir", "secret123")
    assert found.id == user.id
    assert {:error, :invalid_credentials} = Accounts.verify_login("samir", "wrong")
    assert {:error, :invalid_credentials} = Accounts.verify_login("ghost", "secret123")
  end
end
