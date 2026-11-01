# Craft UI redesign · 0.2.0

The redesign covers all nine settings destinations and Quick Access. It introduces a grouped sidebar, a persistent workspace header, explicit notices, overview metrics, an illustrated three-zone guide, searchable/filterable item rows, saved-layout cards, access-status cards and shared editors. Groups, spacers, rules and widgets use a common card system. Appearance and global-spacing controls include clearly labeled illustrative previews. The widget canvas has a dotted grid, numbered nodes, output distinction and visible connection paths.

App-owned labels and status messages are English. Stored user names and text remain untouched. `CraftBrand` owns visible branding; bundle ID, data path, menu item autosave names and Codable identities retain compatibility. The original icon generator uses only AppKit vector drawing.

## Verification checklist

- Build from the committed source, excluding unrelated in-progress movement code.
- Run `BarGardenCoreChecks`; English Boolean rendering is the only changed display expectation, while user-supplied Chinese widget text remains in round-trip checks.
- Normally open the exact candidate. Visit every sidebar destination and Quick Access; inspect overflow, readable empty states, toolbar actions and window resizing.
- Use controlled data for editor journeys; do not grant system permissions or change global spacing just to produce screenshots.
- Confirm original user configuration is preserved. Verify the final signed distribution independently.

UI snapshots, runtime outcomes and release receipts are recorded separately. This document specifies the acceptance journey and does not claim it has already run.
