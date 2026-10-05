defmodule BackendWeb.ClientIPTest do
  # the trusted header is an application setting, shared by everything
  use ExUnit.Case, async: false

  import Backend.RateLimitHelper, only: [put_env: 2]
  import Plug.Test

  alias BackendWeb.ClientIP

  defp conn_from(remote_ip, headers \\ []) do
    conn = conn(:get, "/")
    conn = %{conn | remote_ip: remote_ip}
    Enum.reduce(headers, conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
  end

  describe "where no proxy is trusted (development, tests)" do
    setup do
      Application.delete_env(:backend, :client_ip_header)
      :ok
    end

    test "it is the address the connection came from" do
      assert ClientIP.from_conn(conn_from({203, 0, 113, 7})) == "203.0.113.7"
    end

    test "a header is ignored, so nobody can choose their own address" do
      conn =
        conn_from({203, 0, 113, 7}, [{"fly-client-ip", "1.2.3.4"}, {"x-forwarded-for", "5.6.7.8"}])

      assert ClientIP.from_conn(conn) == "203.0.113.7"
    end
  end

  describe "behind a proxy whose header is trusted" do
    setup do
      put_env(:client_ip_header, "fly-client-ip")
    end

    test "it is the address in that header" do
      conn = conn_from({172, 16, 0, 1}, [{"fly-client-ip", "203.0.113.7"}])
      assert ClientIP.from_conn(conn) == "203.0.113.7"
    end

    test "without the header it falls back to the connection's own address" do
      assert ClientIP.from_conn(conn_from({172, 16, 0, 1})) == "172.16.0.1"
    end

    test "a header that is not an address is ignored" do
      for junk <- ["", "not an ip", "1.2.3", "1.2.3.4; drop table", "999.1.1.1"] do
        conn = conn_from({172, 16, 0, 1}, [{"fly-client-ip", junk}])
        assert ClientIP.from_conn(conn) == "172.16.0.1", inspect(junk)
      end
    end

    test "only the named header counts" do
      conn = conn_from({172, 16, 0, 1}, [{"x-forwarded-for", "203.0.113.7"}])
      assert ClientIP.from_conn(conn) == "172.16.0.1"
    end

    test "surrounding spaces are fine" do
      conn = conn_from({172, 16, 0, 1}, [{"fly-client-ip", " 203.0.113.7 "}])
      assert ClientIP.from_conn(conn) == "203.0.113.7"
    end
  end

  describe "IPv6" do
    test "everyone in the same /64 network is the same caller" do
      a = ClientIP.key({0x2001, 0xDB8, 0xAAAA, 0xBBBB, 1, 2, 3, 4})
      b = ClientIP.key({0x2001, 0xDB8, 0xAAAA, 0xBBBB, 0xFFFF, 0, 9, 9})
      assert a == b
    end

    test "another network is another caller" do
      refute ClientIP.key({0x2001, 0xDB8, 0xAAAA, 0xBBBB, 1, 1, 1, 1}) ==
               ClientIP.key({0x2001, 0xDB8, 0xAAAA, 0xCCCC, 1, 1, 1, 1})
    end

    test "an IPv4 address and an IPv6 network never look the same" do
      refute ClientIP.key({1, 2, 3, 4}) == ClientIP.key({1, 2, 3, 4, 0, 0, 0, 0})
    end
  end

  describe "a WebSocket connection" do
    test "uses the peer's address when no proxy is trusted" do
      Application.delete_env(:backend, :client_ip_header)

      info = %{
        peer_data: %{address: {198, 51, 100, 9}, port: 5, ssl_cert: nil},
        x_headers: [{"fly-client-ip", "1.2.3.4"}]
      }

      assert ClientIP.from_connect_info(info) == "198.51.100.9"
    end

    test "uses the trusted header when there is one" do
      put_env(:client_ip_header, "fly-client-ip")

      info = %{
        peer_data: %{address: {172, 16, 0, 1}, port: 5, ssl_cert: nil},
        x_headers: [{"fly-client-ip", "203.0.113.7"}]
      }

      assert ClientIP.from_connect_info(info) == "203.0.113.7"
    end

    test "copes with nothing to go on" do
      assert ClientIP.from_connect_info(%{}) == "unknown"
    end
  end
end
