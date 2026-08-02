defmodule SuchConfigDesktop.SecuritySentinelTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.SecuritySentinel
  alias SuchConfigDesktop.Vault.Types

  @fixture_report %{
    "schema_version" => 1,
    "findings" => [
      %{
        "id" => "abc123",
        "source" => "osv_scanner",
        "severity" => "high",
        "package" => "regex",
        "version" => "1.5.1",
        "ecosystem" => "crates.io",
        "title" => "Regex DoS",
        "detail" => "Catastrophic backtracking",
        "path" => "/tmp/Cargo.lock",
        "cve_ids" => ["CVE-2022-24713"],
        "fixed_version" => "1.5.5",
        "status" => "open"
      }
    ],
    "allow_list" => [],
    "summary" => %{
      "critical" => 0,
      "high" => 1,
      "medium" => 0,
      "low" => 0,
      "info" => 0
    },
    "recommended_actions" => ["Upgrade regex from 1.5.1 to 1.5.5 (or later)."],
    "risk_score" => 75,
    "overall_grade" => "B",
    "scanners" => [
      %{"name" => "osv-scanner", "status" => "ok", "version" => "2.0.0", "message" => nil}
    ],
    "last_scan" => "2026-07-19T12:00:00Z",
    "linked_project_path" => "/tmp/fixture"
  }

  test "cast_kind accepts security_manifest" do
    assert Types.cast_kind("security_manifest") == {:ok, :security_manifest}
    assert Types.cast_kind(:security_manifest) == {:ok, :security_manifest}
  end

  test "report_card_from_report trusts stored grade" do
    card = SecuritySentinel.report_card_from_report(@fixture_report)
    assert card.overall_grade == "B"
    assert card.risk_score == 75
    assert length(card.top_findings) == 1
    assert hd(card.top_findings)["package"] == "regex"
  end

  @tag :crdt
  test "upsert_manifest persists and reloads report card" do
    unless SuchConfigDesktop.ProjectVault.feature_enabled?() do
      flunk("CRDT NIF required for this test")
    end

    password = "sentinel-manifest-pw"
    folder = project_folder_fixture()

    assert {:ok, item} = SecuritySentinel.upsert_manifest(folder.id, @fixture_report, password)
    assert item.kind == "security_manifest"
    assert item.title == "Security Manifest"

    assert {:ok, _item, report} = SecuritySentinel.get_manifest(folder.id, password)
    assert report["overall_grade"] == "B"
    assert report["risk_score"] == 75

    card = SecuritySentinel.report_card_from_report(report)
    assert card.overall_grade == "B"

    assert {:ok, badge} = SecuritySentinel.risk_badge_for_folder(folder.id, password)
    assert badge.overall_grade == "B"
    assert badge.risk_score == 75

    updated = Map.put(@fixture_report, "risk_score", 40)
    updated = Map.put(updated, "overall_grade", "D")
    assert {:ok, item2} = SecuritySentinel.upsert_manifest(folder.id, updated, password)
    assert item2.id == item.id

    assert {:ok, badge2} = SecuritySentinel.risk_badge_for_folder(folder.id, password)
    assert badge2.overall_grade == "D"
    assert badge2.risk_score == 40
  end

  @tag :crdt
  test "upsert_manifest reclaims reserved title when kind was changed" do
    unless SuchConfigDesktop.ProjectVault.feature_enabled?() do
      flunk("CRDT NIF required for this test")
    end

    password = "sentinel-reclaim-pw"
    folder = project_folder_fixture()

    assert {:ok, item} =
             SuchConfigDesktop.ProjectVault.save_vault_item(
               %{
                 title: "Security Manifest",
                 kind: "generic_note",
                 security_mode: "global_passkey",
                 project_folder_id: folder.id,
                 body: "not a report"
               },
               password
             )

    assert {:ok, updated} = SecuritySentinel.upsert_manifest(folder.id, @fixture_report, password)
    assert updated.id == item.id
    assert updated.kind == "security_manifest"
    assert updated.title == "Security Manifest"

    assert {:ok, _item, report} = SecuritySentinel.get_manifest(folder.id, password)
    assert report["overall_grade"] == "B"
  end
end
