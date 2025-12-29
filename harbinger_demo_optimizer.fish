#!/usr/bin/env fish

# harbinger_demo_optimizer.fish - Test multiple preprocessing configs and pick the best
# Usage: ./harbinger_demo_optimizer.fish --config pipeline_config.json

# Source progress utilities
source (dirname (status filename))/progress_utils.fish

set -g PDF_FILE ""
set -g CONFIG_FILE ""
set -g OUTPUT_ROOT ""
set -g DEMO_ROOT ""

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function log_info
    echo (set_color green)"[INFO]"(set_color normal) $argv >&2
end

function log_warn
    echo (set_color yellow)"[WARN]"(set_color normal) $argv >&2
end

function log_error
    echo (set_color red)"[ERROR]"(set_color normal) $argv >&2
end

function log_step
    echo "" >&2
    echo (set_color cyan)"┌─["(set_color yellow)" $argv[1] "(set_color cyan)"]"(set_color normal) >&2
end

function log_substep
    echo (set_color cyan)"│ "(set_color normal)"$argv" >&2
end

function log_complete
    echo (set_color cyan)"└─"(set_color green)" ✓ Complete"(set_color normal) >&2
end

# ============================================================================
# PREPROCESSING CONFIGURATIONS TO TEST
# ============================================================================

function get_config_presets
    # Returns JSON array of preprocessing configurations to test
    set -l script_dir (dirname (status filename))
    jq '.' "$script_dir/presets.json"
end

# ============================================================================
# CONFIG GENERATION
# ============================================================================

function create_test_config
    set preset_name $argv[1]
    set output_file $argv[2]
    set preset_json $argv[3]

    # Load base config
    if not test -f "$CONFIG_FILE"
        log_error "Config file not found: $CONFIG_FILE"
        return 1
    end

    # Check if this is the "current" preset (use existing config as-is)
    set is_from_config (echo $preset_json | jq -r '.from_config // false')

    if test "$is_from_config" = "true"
        # Just copy the current config
        cp $CONFIG_FILE $output_file
        log_substep "Using current config from $CONFIG_FILE"
        return 0
    end

    # Create modified config with this preset's preprocessing settings
    jq --argjson preset "$preset_json" '
        .preprocessing.despeckle = $preset.despeckle |
        .preprocessing.contrast_stretch = $preset.contrast_stretch |
        .preprocessing.level = $preset.level |
        .preprocessing.morphology = $preset.morphology
    ' $CONFIG_FILE > $output_file
end

# ============================================================================
# RUN SINGLE TEST
# ============================================================================

function run_single_test
    set preset_name $argv[1]
    set preset_json $argv[2]

    log_substep "Testing: $preset_name"

    set test_output "$DEMO_ROOT/test_$preset_name"
    set test_config "$DEMO_ROOT/config_$preset_name.json"

    # Create test config
    create_test_config $preset_name $test_config $preset_json

    # Run conversion with this config
    ./harbinger_master.fish \
        --config $test_config \
        --output $test_output \
        --demo \
        --clean >/dev/null 2>&1

    # Check for confidence report
    if test -f "$test_output/diagnostics/all_confidence_reports.md"
        log_substep "✓ $preset_name completed"
        return 0
    else
        log_warn "✗ $preset_name failed or incomplete"
        return 1
    end
end

# ============================================================================
# ANALYZE RESULTS
# ============================================================================

function analyze_confidence_report
    set report_file $argv[1]

    if not test -f $report_file
        echo "0"
        return
    end

    # Count low-confidence words (lines with "conf:" in them)
    set low_conf_count (grep -c "(conf:" $report_file 2>/dev/null || echo 0)
    echo $low_conf_count
end

function calculate_avg_confidence
    set report_file $argv[1]

    if not test -f $report_file
        echo "0.0"
        return
    end

    # Extract confidence values and calculate average
    grep "(conf:" $report_file | \
        sed 's/.*conf: \([0-9.]*\).*/\1/' | \
        awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print 0}'
end

# ============================================================================
# PRESENT RESULTS
# ============================================================================

function present_results
    echo ""
    echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
    echo (set_color cyan)"║"(set_color normal)(set_color yellow)"          PREPROCESSING CONFIGURATION COMPARISON          "(set_color normal)(set_color cyan)"║"(set_color normal)
    echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
    echo ""

    echo (set_color yellow)"Results from testing different preprocessing configurations:"(set_color normal)
    echo ""

    # Table header
    printf "%-15s %-10s %-10s %s\n" "Config" "Low Conf" "Avg Conf" "Description"
    printf "%-15s %-10s %-10s %s\n" "===============" "==========" "==========" "================================"

    # Analyze each test result
    set presets (get_config_presets | jq -c '.[]')

    for preset_json in $presets
        set preset_name (echo $preset_json | jq -r '.name')
        set preset_desc (echo $preset_json | jq -r '.description')
        set test_output "$DEMO_ROOT/test_$preset_name"
        set report_file "$test_output/diagnostics/all_confidence_reports.md"

        if test -f $report_file
            set low_count (analyze_confidence_report $report_file)
            set avg_conf (calculate_avg_confidence $report_file)

            printf "%-15s %-10s %-10.1f %s\n" $preset_name $low_count $avg_conf $preset_desc
        else
            printf "%-15s %-10s %-10s %s\n" $preset_name "FAILED" "-" $preset_desc
        end
    end

    echo ""
    echo (set_color cyan)"Lower 'Low Conf' count and higher 'Avg Conf' are better"(set_color normal)
    echo ""
end

function prompt_selection
    echo (set_color yellow)"Which configuration would you like to use?"(set_color normal)
    echo ""

    set presets (get_config_presets | jq -c '.[]')
    set idx 1

    for preset_json in $presets
        set preset_name (echo $preset_json | jq -r '.name')
        set preset_desc (echo $preset_json | jq -r '.description')
        echo "  $idx) $preset_name - $preset_desc"
        set idx (math $idx + 1)
    end

    echo ""
    read -P (set_color green)"Enter selection (1-"(count $presets)"): "(set_color normal) selection

    echo $selection
end

function apply_selected_config
    set selection $argv[1]

    set presets (get_config_presets | jq -c '.[]')
    set idx 1
    set selected_preset ""

    for preset_json in $presets
        if test $idx -eq $selection
            set selected_preset $preset_json
            break
        end
        set idx (math $idx + 1)
    end

    if test -z "$selected_preset"
        log_error "Invalid selection"
        return 1
    end

    set preset_name (echo $selected_preset | jq -r '.name')
    set test_config "$DEMO_ROOT/config_$preset_name.json"

    # Copy the selected config to the main pipeline config
    if test -f $test_config
        cp $test_config $CONFIG_FILE
        log_info "Updated $CONFIG_FILE with '$preset_name' configuration"
        return 0
    else
        log_error "Test config not found: $test_config"
        return 1
    end
end

# ============================================================================
# MAIN
# ============================================================================

# Parse arguments
set -l i 1
while test $i -le (count $argv)
    switch $argv[$i]
        case --config -c
            set i (math $i + 1)
            set -g CONFIG_FILE $argv[$i]
        case '*.json'
            set -g CONFIG_FILE $argv[$i]
    end
    set i (math $i + 1)
end

# Validate
if test -z "$CONFIG_FILE"; or not test -f "$CONFIG_FILE"
    log_error "Config file required. Usage: ./harbinger_demo_optimizer.fish --config pipeline_config.json"
    exit 1
end

# Load PDF from config
if command -v jq &>/dev/null
    set -g PDF_FILE (jq -r '.input // empty' $CONFIG_FILE)
else
    log_error "jq is required for this script"
    exit 1
end

if test -z "$PDF_FILE"; or not test -f "$PDF_FILE"
    log_error "PDF file not found. Make sure 'input' is set in $CONFIG_FILE"
    exit 1
end

# Setup paths
set -g OUTPUT_ROOT (jq -r '.output_root // empty' $CONFIG_FILE)
if test -z "$OUTPUT_ROOT"
    set -g OUTPUT_ROOT "converted_"(basename $PDF_FILE .pdf)
end

set -g DEMO_ROOT "$OUTPUT_ROOT/demo_tests"
mkdir -p $DEMO_ROOT

# Banner
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     HARBINGER DEMO OPTIMIZER - Find Best Settings       "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color green)"PDF:         "(set_color normal)"$PDF_FILE"
echo (set_color green)"Config:      "(set_color normal)"$CONFIG_FILE"
echo (set_color green)"Demo Output: "(set_color normal)"$DEMO_ROOT"
echo ""

log_step "Testing Preprocessing Configurations"

set presets (get_config_presets | jq -c '.[]')
set total_tests (count $presets)

log_substep "Will test $total_tests configurations on first page..."
echo ""

# Initialize progress tracking
progress_start $total_tests "Testing configs"

set test_num 1
for preset_json in $presets
    set preset_name (echo $preset_json | jq -r '.name')
    set preset_desc (echo $preset_json | jq -r '.description')

    # Update progress display with current config name
    if is_interactive
        spinner_clear
    end
    echo (set_color cyan)"│ Test $test_num/$total_tests:"(set_color normal)" $preset_name - $preset_desc" >&2
    
    run_single_test $preset_name $preset_json
    
    progress_update $test_num

    set test_num (math $test_num + 1)
end

progress_finish
log_complete

# Present results
present_results

# Prompt for selection
set selection (prompt_selection)

if test -n "$selection"
    if apply_selected_config $selection
        echo ""
        echo (set_color green)"✨ Configuration updated! Run the full pipeline with:"(set_color normal)
        echo "   ./harbinger_master.fish --config $CONFIG_FILE --clean"
    else
        echo ""
        log_error "Failed to apply configuration"
        exit 1
    end
else
    log_warn "No selection made, config unchanged"
end

echo ""
