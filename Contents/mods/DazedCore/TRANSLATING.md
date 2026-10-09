# Translating the Dazed mods

Every piece of text the players see lives in JSON files, one folder per language:

    <mod>/common/media/lua/shared/Translate/EN/*.json      (English, the source)
    <mod>/common/media/lua/shared/Translate/<LANG>/*.json  (your language, same file names)

`<LANG>` is the game's language code: `FR`, `DE`, `ES`, `PTBR`, `RU`, `PL`, `IT`, `CN`, `KO`, `JP` and so on (the
folder names under the game's own `media/lua/shared/Translate`).

## Start a language

    python3 DazedCore/tools/translation_kit.py start DazedPower FR
    python3 DazedCore/tools/translation_kit.py start DazedPlumbing FR
    python3 DazedCore/tools/translation_kit.py start DazedCore FR

That copies every key into `Translate/FR/` in English. Translate the values, never the keys. Run `start` again
after an update: it keeps what you already translated and only adds the new keys.

## Rules

- Keep the placeholders exactly: `%1`, `%2`, `{1}`, `%%` (a literal percent sign) and rich-text tags such as
  `<LINE>`, `<H1>`, `<TEXT>` in the guide pages.
- Keys built from a kind (`IGUI_DazedPower_Load_waterpump`, `IGUI_DazedPower_SrcState_turning`) must all be present,
  even if a search of the code doesn't find them.
- The guide window's pages are in DazedCore's `IG_UI.json` (`IGUI_DazedGuide_*`).

## Check your work

    python3 DazedCore/tools/translation_kit.py check DazedPower FR

It lists keys still missing, keys the mod no longer uses, lines whose placeholders differ from English (these
break in game) and lines still in English.

Send the finished `Translate/<LANG>` folders as a pull request on GitHub (Dazedgenie/DazedPower, DazedPlumbing,
DazedCore). Translations are credited in each mod's README.
