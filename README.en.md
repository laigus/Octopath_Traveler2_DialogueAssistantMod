# Octopath Dialogue Assistant

[简体中文](README.md) | English

A dialogue-focused language-learning mod for *OCTOPATH TRAVELER II*. It includes:

- **Replay current line**: Replays the current dialogue box, original voice, camera, and character performance. The default key is `R`.
- **Previous line**: Replays the complete performance for the previous line, then returns to the current story position. The default key is `G`.
- **Official translation**: Displays the game's official text for the current line in the upper-right corner during story scenes. The key is configurable and defaults to `T`; the default translation language is Simplified Chinese.
- **Language analysis**: Displays vocabulary, readings, parts of speech, grammar, and supplementary notes for the current Japanese line. The key is configurable and defaults to `V`; the default analysis language is Japanese.
- **Key hints**: Shows shortcut hints in the corner during story scenes.
- **Configuration**: Adds a configuration category to the in-game Options menu for feature toggles, shortcut keys, translation language, and analysis language.

## In-Game Mod Settings

Open the game's Options menu and select the `DIALOGUE ASSISTANT` category with the native-style icon. The mod creates eight settings in the right-hand list:

- `DIALOGUE REPLAY`: Use Left/Right or Confirm to enable or disable replay and previous-line playback.
- `REPLAY CURRENT KEY`: Confirm the item, then press any letter to assign the replay-current shortcut.
- `PREVIOUS LINE KEY`: Confirm the item, then press any letter to assign the previous-line shortcut.
- `TRANSLATION`: Use Left/Right or Confirm to enable or disable official translations.
- `TRANSLATION LANGUAGE`: Use Left/Right to select the translation language.
- `TRANSLATION KEY`: Confirm the item, then press any letter to assign the show/hide translation shortcut.
- `ANALYSIS LANGUAGE`: Use Left/Right to select the language to analyze.
- `ANALYSIS KEY`: Confirm the item, then press any letter to assign the show/hide analysis shortcut. It is currently available only when the analysis language is Japanese.

The translation and analysis language selectors use the same nine-language list as the game's native `Text Language` setting: Japanese, English, Italian, French, German, Spanish, Traditional Chinese, Simplified Chinese, and Korean. Only Japanese analysis data is currently included. Selecting another analysis language disables `ANALYSIS KEY`, its shortcut hint, and the analysis action.

## Supported Version

- Steam App `1971650`
- Analyzed build `13399590`
- Unreal Engine `4.27.2`
- Executable SHA256: `409648E864CEEC5CA0E57A493B39D808B54BEF1E183C674F7F40CEDEDACFDBCF`
- UE4SS `3.0.1`

## Install or Update

Download `OctopathDialogueAssistant-<version>.zip` from [Releases](https://github.com/laigus/Octopath_Traveler2_DialogueAssistantMod/releases/latest). The package includes the pinned UE4SS 3.0.1 runtime, official text lookup data for all nine languages, and Japanese analysis data. Extract the complete archive, exit the game, and double-click `OctopathDialogueAssistantInstaller.exe` inside it:

1. Click `选择目录` (Select Folder) and select the `Octopath_Traveler2` folder under the Steam `common` directory.
2. Click `安装 / 更新` (Install / Update).
3. Start the game after the window reports `安装完成` (Installation Complete).

You can also install from the extracted package root with PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -GameRoot "<Octopath_Traveler2 folder under Steam common>"
```

The installer adds the pinned UE4SS files, `Mods\OctopathDialogueAssistant`, and the enable line in `mods.txt` under `Binaries\Win64`. It also copies `OctopathDialogueAssistant_P.pak` to the game's `Content\Paks` directory. The nine official text lookup files and the read-only `analysis_ja.tsv` are installed with the mod. The separate override PAK adds the Options category and supplements the Simplified Chinese font used by the analysis panel with Japanese glyphs. It leaves the game's main PAK, executable, and save data unchanged. Updates preserve the user's `config.lua`; uninstalling removes the mod PAK, runtime code, and lookup data.

The runtime log is located at `Binaries\Win64\UE4SS.log` inside the game directory.

## Uninstall

Exit the game, open `OctopathDialogueAssistantInstaller.exe`, select the same game directory, and click `卸载` (Uninstall). You can also run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\uninstall.ps1 -GameRoot "<Octopath_Traveler2 folder under Steam common>"
```

The uninstaller reads the mod's installation manifest and restores the pre-installation state. Files added by this installation, including the mod PAK and UE4SS, are removed. Matching pre-existing files are retained, while updated files are restored from the installation backup.

The TSV files, PAK, UE4SS archive, and graphical installer in the source workspace are generated artifacts excluded from Git. Developers can find the complete generation and release workflow in [Architecture](https://github.com/laigus/Octopath_Traveler2_DialogueAssistantMod/blob/main/docs/architecture.md). For confirmed game objects and behavior, see [Research Notes](https://github.com/laigus/Octopath_Traveler2_DialogueAssistantMod/blob/main/docs/research.md). Both documents are currently written in Chinese.
