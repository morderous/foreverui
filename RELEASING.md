# Releasing ForeverUI

A release is what ForeverUI Manager installs as the `ForeverUI` addon of the pack, and where people download the manager itself. Each one holds:

- `ForeverUI-<version>.zip`: the `ForeverUI`, `ForeverUI_XPBar`, `ForeverUI_QuestLog` and `ForeverUI_Trainer` folders.
- `release.json`: says which zip is for WoW Forever (flavor `forever`, Interface 16001), the way addon packagers write it. ForeverUI Manager, and other addon managers, pick the zip by it.
- `SHA256SUMS`: the sha256 of the zip and of the exe. The manager checks the zip against it and against GitHub's own sha256.
- `ForeverUIManager.exe`: the manager, built from `manager/`.

The tag is `v<version>`, the version in `addons/ForeverUI/ForeverUI.toc`.

## Steps

1. **The look.** In the game, `/fui capture`, then `/reload`. Then `python -I tools/make_profile.py`, and review `profiles/` (the diff shows what changed in the look).
2. **Versions.** Raise `## Version` in `addons/ForeverUI/ForeverUI.toc`, in `addons/ForeverUI_XPBar/ForeverUI_XPBar.toc` when the bar changed, in `addons/ForeverUI_QuestLog/ForeverUI_QuestLog.toc` when the quest log changed, and in `addons/ForeverUI_Trainer/ForeverUI_Trainer.toc` when the trainer changed (after `python -I tools/make_trainer_data.py <WhatsTraining folder>` when What's Training? brought new data). For a new manager, raise `Core.Version` and the two `Assembly*Version` lines at the top of `manager/ForeverUIManager.cs`.
3. **Checks.** `sh manager/tests/run_tests.sh` (offline, must say `0 failed`). With GitHub's API limit full, `python -I manager/tests/window_test.py` too (it spends about 50 of the 60 calls an hour; `FUM_NO_API=1` asks GitHub's pages only).
4. **Build.** `python -I tools/make_release.py`. It refuses an empty `Profile.lua`, a font or a program in an addon folder, a `.toc` for another Interface, or an exe whose version is not the manager's. It writes everything into `dist/v<version>/` (not in git).
5. **Check the build as the manager reads it.** `sh manager/tests/run_tests.sh release dist/v<version>`: `release.json` picks the zip, `SHA256SUMS` agrees, the zip installs its two folders into a test AddOns.
6. **Commit and push** `main`.
7. **Release** `v<version>` from that commit, marked latest, with the four files of `dist/v<version>/`. Then download each asset back and compare its sha256 with `SHA256SUMS`.
8. **Read it back as a player would.** `https://github.com/morderous/foreverui/releases/latest` lands on the new tag, and `https://raw.githubusercontent.com/morderous/foreverui/main/pack.json` is the `pack.json` just pushed.

## Notes

- The exe is not signed. Some antivirus programs flag unsigned exes they have not seen before (Kaspersky once deleted it); say so in the release notes, with the sha256 to check it against.
- Never ship fonts: the profile uses the fonts that come with EllesmereUI.
- `pack.json` takes effect when it is pushed to `main`, with or without a release: the manager reads it from there every 6 hours and when **Check now** is clicked. A new extra comes ticked unless it has `"ticked": false`; an addon taken off the pack stays on people's lists, no longer required.
