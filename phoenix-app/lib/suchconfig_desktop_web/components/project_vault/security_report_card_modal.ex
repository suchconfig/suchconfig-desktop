defmodule SuchConfigDesktopWeb.Components.ProjectVault.SecurityReportCardModal do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Modal

  alias SuchConfigDesktopWeb.Components.ProjectVault.SentinelUpgradeCard

  attr :show, :boolean, default: false
  attr :card, :map, default: nil
  attr :scanning, :boolean, default: false
  attr :scan_percent, :integer, default: 0
  attr :scan_message, :string, default: nil
  attr :error, :string, default: nil
  attr :license_enabled?, :boolean, default: false

  def security_report_card_modal(assigns) do
    card = assigns.card || %{}
    summary = Map.get(card, :summary) || Map.get(card, "summary") || %{}
    grade = Map.get(card, :overall_grade) || Map.get(card, "overall_grade") || "—"
    score = Map.get(card, :risk_score) || Map.get(card, "risk_score") || 0
    findings = Map.get(card, :top_findings) || Map.get(card, "top_findings") || []
    actions = Map.get(card, :recommended_actions) || Map.get(card, "recommended_actions") || []
    scanners = Map.get(card, :scanners) || Map.get(card, "scanners") || []
    last_scan = Map.get(card, :last_scan) || Map.get(card, "last_scan")

    assigns =
      assign(assigns,
        grade: grade,
        score: score,
        summary: summary,
        findings: findings,
        actions: actions,
        scanners: scanners,
        last_scan: last_scan,
        grade_tone: grade_tone(grade)
      )

    ~H"""
    <.modal_shell
      show={@show || @scanning}
      id="sentinel-report-card-modal"
      on_cancel="close_sentinel_report_modal"
      size="lg"
    >
      <.modal_head>
        <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; width: 100%">
          <div style="flex: 1; min-width: 0">
            <h3 style="margin: 0">Security Report Card</h3>
            <p class="modal-hint" style="margin-top: 4px">
              Local scan via osv-scanner and grype. Findings stay on this device in your vault.
            </p>
          </div>
          <button
            type="button"
            class="btn ghost sm icon-only close"
            phx-click="close_sentinel_report_modal"
            aria-label="Close"
          >
            <.icon name="x" size={14} />
          </button>
        </div>
      </.modal_head>
      <.modal_body>
        <SentinelUpgradeCard.sentinel_upgrade_card :if={!@license_enabled?} />

        <div :if={@license_enabled? and @error} class="vault-flash err" role="alert">{@error}</div>

        <div :if={@license_enabled? and @scanning} style="padding: 8px 0 16px">
          <p style="margin: 0; font-weight: 500">{@scan_message || "Scanning…"}</p>
          <div
            style="margin-top: 10px; height: 8px; border-radius: 999px; background: var(--line, #e5e7eb); overflow: hidden"
            role="progressbar"
            aria-valuenow={@scan_percent}
            aria-valuemin="0"
            aria-valuemax="100"
          >
            <div style={"height: 100%; width: #{@scan_percent}%; background: var(--ink, #111); transition: width 0.2s ease"} />
          </div>
        </div>

        <div :if={@license_enabled? and not @scanning and @card} style="display: grid; gap: 16px">
          <div style="display: flex; align-items: center; gap: 16px; flex-wrap: wrap">
            <div style={"width: 72px; height: 72px; border-radius: 12px; display: grid; place-items: center; font-size: 28px; font-weight: 700; border: 1px solid; #{@grade_tone}"}>
              {@grade}
            </div>
            <div>
              <div style="font-size: 14px; opacity: 0.7">Risk score</div>
              <div style="font-size: 22px; font-weight: 600">{@score}/100</div>
              <div :if={@last_scan} style="font-size: 12px; opacity: 0.65; margin-top: 4px">
                Last scan {@last_scan}
              </div>
            </div>
          </div>

          <div style="display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 8px">
            <.stat_chip label="Critical" value={summary_val(@summary, :critical)} />
            <.stat_chip label="High" value={summary_val(@summary, :high)} />
            <.stat_chip label="Medium" value={summary_val(@summary, :medium)} />
            <.stat_chip label="Low" value={summary_val(@summary, :low)} />
            <.stat_chip label="Info" value={summary_val(@summary, :info)} />
          </div>

          <div>
            <h4 style="margin: 0 0 8px; font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.7">
              Top findings
            </h4>
            <p :if={@findings == []} style="margin: 0; opacity: 0.75">No open findings.</p>
            <ul :if={@findings != []} style="margin: 0; padding-left: 18px; display: grid; gap: 8px">
              <li :for={f <- @findings}>
                <strong>{finding_get(f, "package")}</strong>
                <span style="opacity: 0.7">{finding_get(f, "version")}</span>
                — {finding_get(f, "title")}
                <span style="opacity: 0.65"> ({finding_get(f, "severity")})</span>
              </li>
            </ul>
          </div>

          <div>
            <h4 style="margin: 0 0 8px; font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.7">
              Recommended actions
            </h4>
            <ul style="margin: 0; padding-left: 18px; display: grid; gap: 6px">
              <li :for={action <- @actions}>{action}</li>
            </ul>
          </div>

          <div :if={@scanners != []}>
            <h4 style="margin: 0 0 8px; font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.7">
              Scanners
            </h4>
            <ul style="margin: 0; padding-left: 18px; font-size: 13px">
              <li :for={s <- @scanners}>
                {scanner_get(s, "name")} — {scanner_get(s, "status")}
                <span :if={scanner_get(s, "message")} style="opacity: 0.7">
                  ({scanner_get(s, "message")})
                </span>
              </li>
            </ul>
          </div>
        </div>
      </.modal_body>
      <div
        class="modal-foot"
        style="display: flex; gap: 8px; justify-content: flex-end; flex-wrap: wrap"
      >
        <button
          type="button"
          class="btn ghost"
          id="sentinel-upgrade-close-button"
          phx-click="close_sentinel_report_modal"
          disabled={@scanning}
        >
          Close
        </button>
        <button
          :if={@license_enabled?}
          type="button"
          class="btn ghost"
          phx-click="sentinel_view_manifest"
          disabled={@scanning or is_nil(@card)}
        >
          View Security Manifest
        </button>
        <button
          :if={@license_enabled?}
          type="button"
          class="btn primary"
          phx-click="sentinel_rescan"
          disabled={@scanning}
        >
          Rescan Project
        </button>
      </div>
    </.modal_shell>
    """
  end

  defp stat_chip(assigns) do
    ~H"""
    <div style="border: 1px solid var(--line, #e5e7eb); border-radius: 8px; padding: 8px; text-align: center">
      <div style="font-size: 11px; opacity: 0.65">{@label}</div>
      <div style="font-size: 18px; font-weight: 600">{@value}</div>
    </div>
    """
  end

  defp summary_val(summary, key) do
    Map.get(summary, key) || Map.get(summary, Atom.to_string(key)) || 0
  end

  defp finding_get(f, key) when is_map(f) and is_binary(key) do
    Map.get(f, key) || ""
  end

  defp finding_get(_, _), do: ""

  defp scanner_get(s, key) when is_map(s) and is_binary(key) do
    Map.get(s, key)
  end

  defp scanner_get(_, _), do: nil

  defp grade_tone("A"), do: "border-color: #166534; color: #166534; background: #f0fdf4"
  defp grade_tone("B"), do: "border-color: #1d4ed8; color: #1d4ed8; background: #eff6ff"
  defp grade_tone("C"), do: "border-color: #a16207; color: #a16207; background: #fefce8"
  defp grade_tone("D"), do: "border-color: #c2410c; color: #c2410c; background: #fff7ed"
  defp grade_tone(_), do: "border-color: #b91c1c; color: #b91c1c; background: #fef2f2"
end
