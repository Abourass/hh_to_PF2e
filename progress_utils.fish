#!/usr/bin/env fish

# progress_utils.fish - Shared progress bar and ETA utilities
# Source this file in your scripts: source (dirname (status filename))/progress_utils.fish

# ============================================================================
# TERMINAL DETECTION
# ============================================================================

function is_interactive
    # Returns 0 (true) if running in an interactive terminal, 1 otherwise
    # Progress bars should only display in interactive mode to avoid polluting logs
    test -t 2
end

function get_terminal_width
    # Get terminal width, default to 80 if not available
    set -l width 80
    if command -v tput &>/dev/null
        set width (tput cols 2>/dev/null)
        if test -z "$width"; or test "$width" -lt 20
            set width 80
        end
    end
    echo $width
end

# ============================================================================
# TIME FORMATTING
# ============================================================================

function format_duration
    # Format seconds into human-readable duration
    # Usage: format_duration 3661 -> "1h 1m 1s"
    set -l seconds $argv[1]
    
    if test -z "$seconds"; or test "$seconds" -lt 0
        echo "0s"
        return
    end
    
    set -l hours (math --scale=0 "$seconds / 3600")
    set -l minutes (math --scale=0 "($seconds % 3600) / 60")
    set -l secs (math --scale=0 "$seconds % 60")
    
    if test $hours -gt 0
        echo "$hours"h" $minutes"m" $secs"s
    else if test $minutes -gt 0
        echo "$minutes"m" $secs"s
    else
        echo "$secs"s
    end
end

function format_eta
    # Format ETA with "ETA: " prefix
    # Usage: format_eta 120 -> "ETA: 2m 0s"
    set -l seconds $argv[1]
    
    if test -z "$seconds"; or test "$seconds" -le 0
        echo "ETA: --"
        return
    end
    
    echo "ETA: "(format_duration $seconds)
end

# ============================================================================
# PROGRESS BAR RENDERING
# ============================================================================

function render_progress_bar
    # Render a progress bar string
    # Usage: render_progress_bar current total [bar_width]
    # Returns: [████████████░░░░░░░░] 60%
    
    set -l current $argv[1]
    set -l total $argv[2]
    set -l bar_width $argv[3]
    
    if test -z "$bar_width"
        set bar_width 30
    end
    
    if test "$total" -eq 0
        set total 1
    end
    
    set -l percent (math --scale=0 "$current * 100 / $total")
    set -l filled (math --scale=0 "$bar_width * $current / $total")
    set -l empty (math "$bar_width - $filled")
    
    # Ensure non-negative values
    if test $filled -lt 0
        set filled 0
    end
    if test $empty -lt 0
        set empty 0
    end
    
    set -l bar_filled (string repeat -n $filled "█")
    set -l bar_empty (string repeat -n $empty "░")
    
    printf "[%s%s] %3d%%" $bar_filled $bar_empty $percent
end

# ============================================================================
# PROGRESS STATE MANAGEMENT
# ============================================================================

# Global state for progress tracking
set -g __progress_start_time 0
set -g __progress_label ""
set -g __progress_current 0
set -g __progress_total 0

function progress_start
    # Initialize progress tracking
    # Usage: progress_start total "Processing items"
    set -g __progress_total $argv[1]
    set -g __progress_label $argv[2]
    set -g __progress_current 0
    set -g __progress_start_time (date +%s)
    
    # Show initial state
    if is_interactive
        progress_show 0
    else
        echo "│ $__progress_label (0/$__progress_total)..." >&2
    end
end

function progress_update
    # Update progress to a specific value or increment
    # Usage: progress_update [current] or progress_update +1
    if test "$argv[1]" = "+1"
        set -g __progress_current (math $__progress_current + 1)
    else if test -n "$argv[1]"
        set -g __progress_current $argv[1]
    else
        set -g __progress_current (math $__progress_current + 1)
    end
    
    if is_interactive
        progress_show $__progress_current
    end
end

function progress_show
    # Display current progress with bar and ETA
    # Usage: progress_show current
    set -l current $argv[1]
    
    if not is_interactive
        return
    end
    
    set -l term_width (get_terminal_width)
    
    # Calculate available space for progress bar
    # Format: "│ Label [████░░░░] 50% (5/10) ETA: 1m 30s"
    # Reserve space for: prefix(2) + label(var) + bar(var) + percent(5) + count(var) + eta(var)
    
    set -l count_str "($current/$__progress_total)"
    set -l eta_str ""
    
    # Calculate ETA
    if test $current -gt 0
        set -l elapsed (math (date +%s) - $__progress_start_time)
        set -l per_item (math --scale=2 "$elapsed / $current")
        set -l remaining (math --scale=0 "$per_item * ($__progress_total - $current)")
        set eta_str (format_eta $remaining)
    else
        set eta_str "ETA: --"
    end
    
    # Calculate bar width based on available space
    # Total: prefix(2) + space(1) + label + space(1) + bar + space(1) + percent(4) + space(1) + count + space(1) + eta
    set -l fixed_width (math "2 + 1 + "(string length $__progress_label)" + 1 + 2 + 5 + 1 + "(string length $count_str)" + 1 + "(string length $eta_str))
    set -l bar_width (math "$term_width - $fixed_width")
    
    # Ensure minimum bar width
    if test $bar_width -lt 10
        set bar_width 10
    end
    if test $bar_width -gt 50
        set bar_width 50
    end
    
    set -l progress_bar (render_progress_bar $current $__progress_total $bar_width)
    
    # Use carriage return to overwrite previous line
    printf "\r%s│%s %s %s %s %s" \
        (set_color cyan) \
        (set_color normal) \
        "$__progress_label" \
        "$progress_bar" \
        (set_color blue)"$count_str"(set_color normal) \
        (set_color yellow)"$eta_str"(set_color normal) >&2
end

function progress_finish
    # Complete progress and show final stats
    # Usage: progress_finish ["Custom completion message"]
    set -l message $argv[1]
    
    if test -z "$message"
        set message "Complete"
    end
    
    set -l elapsed (math (date +%s) - $__progress_start_time)
    set -l elapsed_str (format_duration $elapsed)
    
    if is_interactive
        # Clear line and show completion
        printf "\r%s│%s %s %s (%d/%d) in %s\n" \
            (set_color cyan) \
            (set_color green)" ✓ "(set_color normal) \
            "$__progress_label" \
            (set_color green)"$message"(set_color normal) \
            $__progress_total $__progress_total \
            (set_color yellow)"$elapsed_str"(set_color normal) >&2
    else
        echo "│ ✓ $__progress_label $message ($__progress_total/$__progress_total) in $elapsed_str" >&2
    end
    
    # Reset state
    set -g __progress_start_time 0
    set -g __progress_current 0
    set -g __progress_total 0
    set -g __progress_label ""
end

# ============================================================================
# SPINNER FOR INDETERMINATE OPERATIONS
# ============================================================================

set -g __spinner_chars "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"
set -g __spinner_idx 1
set -g __spinner_pid 0

function spinner_tick
    # Advance spinner by one frame
    # Usage: spinner_tick "Processing..."
    set -l message $argv[1]
    
    if not is_interactive
        return
    end
    
    set -l char $__spinner_chars[$__spinner_idx]
    set -g __spinner_idx (math "($__spinner_idx % "(count $__spinner_chars)") + 1")
    
    printf "\r%s│%s %s %s" \
        (set_color cyan) \
        (set_color normal) \
        (set_color yellow)"$char"(set_color normal) \
        "$message" >&2
end

function spinner_clear
    # Clear spinner line
    if is_interactive
        set -l term_width (get_terminal_width)
        printf "\r%s\r" (string repeat -n $term_width " ") >&2
    end
end

# ============================================================================
# PIPELINE STEP PROGRESS
# ============================================================================

set -g __pipeline_current_step 0
set -g __pipeline_total_steps 0
set -g __pipeline_start_time 0

function pipeline_init
    # Initialize pipeline progress
    # Usage: pipeline_init total_steps
    set -g __pipeline_total_steps $argv[1]
    set -g __pipeline_current_step 0
    set -g __pipeline_start_time (date +%s)
end

function pipeline_step
    # Start a new pipeline step
    # Usage: pipeline_step "Step Name"
    set -g __pipeline_current_step (math $__pipeline_current_step + 1)
    set -l step_name $argv[1]
    
    set -l step_indicator "[$__pipeline_current_step/$__pipeline_total_steps]"
    
    echo "" >&2
    echo (set_color cyan)"┌─"(set_color yellow)"$step_indicator"(set_color cyan)" [ $step_name ]"(set_color normal) >&2
end

function pipeline_summary
    # Show pipeline completion summary
    set -l elapsed (math (date +%s) - $__pipeline_start_time)
    set -l elapsed_str (format_duration $elapsed)
    
    echo "" >&2
    echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal) >&2
    echo (set_color cyan)"║"(set_color green)" ✓ Pipeline Complete"(set_color normal)"                                     "(set_color cyan)"║"(set_color normal) >&2
    echo (set_color cyan)"║"(set_color normal)"   Steps: $__pipeline_total_steps | Time: $elapsed_str                               "(set_color cyan)"║"(set_color normal) >&2
    echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal) >&2
end
