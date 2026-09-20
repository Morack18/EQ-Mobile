#!/usr/bin/env bash
set -euo pipefail

# Builds exactly the classic Halas appearance combinations referenced by
# data/halas_npcs_source.json.  These are baked GLBs because Godot imports a
# GLB material set as part of its PackedScene.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exports_dir="${EQ_MOBILE_LANTERN_EXPORTS:-/tmp/lantern-halas-intermediate/Exports}"
# Classic BAM combines global4_chr model data with global3_chr shared ELM
# animations in one Intermediate export root.
classic_bam_exports_dir="${EQ_MOBILE_CLASSIC_BAM_EXPORTS:-/tmp/lantern-player-bam-intermediate/Exports}"
output_dir="${1:-$project_dir/assets/imported/halas/characters}"
builder="$project_dir/resources/LanternExtractor/tools/eqmob-gui/backend/eqmob_glb.py"

mkdir -p "$output_dir"

build_humanoid() {
  local family="$1" skin="$2" head="$3" source_exports="${4:-$exports_dir}"
  python3 "$builder" --exports "$source_exports" --game \
    --animation swimming='l06|l09' --animation treading='l08|p07' \
    --skin "$skin" --head "$head" \
    --face-uv normal --torso-uv normal \
    --flip-part he --flip-part ch --flip-part ua --flip-part fa \
    --flip-part hn --flip-part lg --flip-part ft \
    --output "$output_dir/${family}_s${skin}_h${head}.glb" "$family"
}

build_wolf() {
  local skin="$1" head="$2"
  python3 "$builder" --exports "$exports_dir" --game \
    --animation swimming='l06|l09' --animation treading='l08|p07' \
    --skin "$skin" --head "$head" \
    --face-uv normal --torso-uv normal \
    --flip-part he --flip-part ch --flip-part lg --flip-part ft \
    --output "$output_dir/wol_s${skin}_h${head}.glb" wol
}

# Key: family_s<texture>_h<face>.  Values were generated from the selected
# classic source roster, after safely clamping to each original model's actual
# skin/head tables.
build_humanoid baf 2 3
build_humanoid baf 3 3
# This player fixture variant is not part of the Halas NPC source roster.
build_humanoid bam 0 0 "$classic_bam_exports_dir"
build_humanoid bam 2 0
build_humanoid bam 2 1
build_humanoid bam 2 2
build_humanoid bam 2 3
build_humanoid bam 3 2
build_humanoid bam 3 3
build_humanoid hlf 0 0
build_humanoid hlm 0 0
build_humanoid hlm 1 0
build_humanoid huf 1 3
build_humanoid hum 2 3
build_humanoid hum 4 0
build_wolf 0 0
