defmodule SuchConfigDesktop.SecretsVault.KindFieldsTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.SecretsVault.KindFields

  test "normalize_kind/1 maps login alias to password" do
    assert KindFields.normalize_kind("login") == "password"
    assert KindFields.normalize_kind("password") == "password"
  end

  test "build_frontmatter/2 only includes fields for the active kind" do
    assert KindFields.build_frontmatter("password", %{
             username: "alice",
             url: "https://example.com",
             public_key: "ignored",
             fingerprint: "ignored"
           }) == %{"username" => "alice", "url" => "https://example.com"}

    assert KindFields.build_frontmatter("ssh_key", %{
             username: "ignored",
             url: "ignored",
             public_key: "ssh-rsa AAAA",
             fingerprint: "SHA256:abc"
           }) == %{"public_key" => "ssh-rsa AAAA", "fingerprint" => "SHA256:abc"}
  end

  test "shows_generator?/1 for login and api key only" do
    assert KindFields.shows_generator?("password")
    assert KindFields.shows_generator?("api_key")
    refute KindFields.shows_generator?("ssh_key")
    refute KindFields.shows_generator?("secure_note")
  end
end
