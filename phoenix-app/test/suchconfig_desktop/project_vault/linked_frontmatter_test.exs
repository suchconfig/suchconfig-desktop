defmodule SuchConfigDesktop.ProjectVault.LinkedFrontmatterTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter

  test "content_fingerprint normalizes line endings" do
    a = LinkedFrontmatter.content_fingerprint("a\r\nb")
    b = LinkedFrontmatter.content_fingerprint("a\nb")
    assert a == b
  end

  test "import_bundle sets relative path and hash" do
    bundle = LinkedFrontmatter.import_bundle(".env", "KEY=1\n", 1_700_000_000)
    assert bundle["linked_relative_path"] == ".env"
    assert is_binary(bundle["linked_content_sha256"])
    assert bundle["linked_sync_mode"] == "manual"
  end
end
