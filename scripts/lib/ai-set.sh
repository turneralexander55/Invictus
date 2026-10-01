# shellcheck shell=bash
# The AI set (design-no-ai.md, "AI set"): what a No AI machine must not
# have. Installed as /usr/lib/invictus/lib/ai-set.sh by invictus-sys, so
# `invictus-sys ai on|off` and the tests read the same list.
#   AI_METAS      our metas that may pull it
#   AI_PKGS       every name in the set, ours and Arch's: `ai off` removes
#                 whichever of these are installed
#   AI_ON_INSTALL what `ai on` installs (the rest comes as its dependencies)
# Add a package here when it joins the set (a local model runtime,
# invictus-collegium when it exists).
# shellcheck disable=SC2034 # read by the scripts that source this
AI_METAS="invictus-moneta invictus-voice"
# shellcheck disable=SC2034
AI_PKGS="claude-code whisper-cpp ggml-vulkan invictus-collegium $AI_METAS"
# shellcheck disable=SC2034
AI_ON_INSTALL="invictus-moneta"
