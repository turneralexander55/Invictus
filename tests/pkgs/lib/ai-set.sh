# shellcheck shell=bash
# The AI set (design-no-ai.md, "AI set"): what a No AI machine must not
# have. AI_METAS are our metas that may pull it; AI_PKGS is every name in
# the set, ours and Arch's. Add a package here when it joins the set (a
# local model runtime, invictus-collegium when it exists).
# shellcheck disable=SC2034 # read by the scripts that source this
AI_METAS="invictus-moneta invictus-voice"
# shellcheck disable=SC2034
AI_PKGS="claude-code whisper-cpp ggml-vulkan invictus-collegium $AI_METAS"
