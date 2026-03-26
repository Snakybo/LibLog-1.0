* This codebase is for a World of Warcraft library
* Use Lua 5.1. Do not suggest Lua 5.2+ syntax.
* Consult sources:
  * https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
  * https://warcraft.wiki.gg/wiki/Widget_API
  * https://www.lua.org/manual/5.1/
  * https://github.com/Gethe/wow-ui-source

Always follow existing code conventions:
* PascalCase for functions
* PascalCase for enum-like types (annotated with `--- @enum`)
* PascalCase for 'classes' (e.g. `Logger = Prototype`)
* UPPER_CASE for constants, no changes in syntax, but for readability
* UPPER_CASE for enum keys
* camelCase for variables

NEVER provide potentially incorrect information, when unsure certain functionality exists, state your uncertainty and do not guess.

Always include type annotations in the form of LuaLS comments.
