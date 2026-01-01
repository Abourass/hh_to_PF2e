#!/usr/bin/env fish

# interactive_preprocessing_server.fish - Launch interactive preprocessing UI
# Usage: ./interactive_preprocessing_server.fish <output_root> [config_file]

set OUTPUT_ROOT $argv[1]
set CONFIG_FILE ""

if test (count $argv) -ge 2
    set CONFIG_FILE $argv[2]
end

if test -z "$OUTPUT_ROOT"
    echo (set_color red)"[ERROR]"(set_color normal) "Usage: ./interactive_preprocessing_server.fish <output_root> [config_file]"
    exit 1
end

if not test -d "$OUTPUT_ROOT"
    echo (set_color red)"[ERROR]"(set_color normal) "Output directory not found: $OUTPUT_ROOT"
    exit 1
end

# Find all pages needing preprocessing
set chapters (find $OUTPUT_ROOT -type d -name ".temp" -not -path "*/final/*" -not -path "*/statblocks/*" -not -path "*/diagnostics/*" 2>/dev/null)

if test (count $chapters) -eq 0
    echo (set_color yellow)"[WARN]"(set_color normal) "No chapters with .temp directories found in $OUTPUT_ROOT"
    echo (set_color yellow)"[WARN]"(set_color normal) "Run batch_convert.fish first to extract pages"
    exit 0
end

# Create session manifest
set session_file "$OUTPUT_ROOT/.interactive_session.json"
echo (set_color green)"[INFO]"(set_color normal) "Creating session file: $session_file"

# Initialize session JSON
echo '{"chapters": [], "status": "active", "processedPages": [], "totalPages": 0}' > $session_file

# Populate with chapters and pages
set total_pages 0
for chapter_temp in $chapters
    set chapter_name (basename (dirname $chapter_temp))
    set pages (find $chapter_temp -name "page-*.png" -not -name "*-processed.png" -not -name "*-cleaned.png" -not -name "*-column-*.png" | sort)
    set page_count (count $pages)

    if test $page_count -eq 0
        continue
    end

    set total_pages (math $total_pages + $page_count)

    # Convert pages array to JSON
    set pages_json "["
    set first true
    for page in $pages
        if test "$first" = "true"
            set first false
        else
            set pages_json "$pages_json,"
        end
        set pages_json "$pages_json\"$page\""
    end
    set pages_json "$pages_json]"

    # Add to session JSON (using jq if available, otherwise manual JSON)
    if command -v jq &>/dev/null
        jq ".chapters += [{\"name\": \"$chapter_name\", \"pages\": $pages_json}] | .totalPages = $total_pages" $session_file > $session_file.tmp
        mv $session_file.tmp $session_file
    else
        echo (set_color yellow)"[WARN]"(set_color normal) "jq not found, using basic JSON (may not work correctly)"
    end

    echo (set_color green)"  ✓"(set_color normal) "Chapter: $chapter_name ($page_count pages)"
end

echo (set_color cyan)"Total pages to process: $total_pages"(set_color normal)
echo ""

# Convert session file to absolute path before changing directories
set session_file_abs (realpath $session_file)

# Start Node.js backend server
echo (set_color cyan)"Starting backend server..."(set_color normal)
cd interactive-server
pnpm start $session_file_abs 3001 &
set SERVER_PID $last_pid
cd ..

# Wait for server to start
sleep 2

# Start Vite dev server
echo (set_color cyan)"Starting frontend..."(set_color normal)
cd interactive-preprocessing
pnpm run dev -- --port 3000 &
set VITE_PID $last_pid
cd ..

# Wait a moment for Vite to start
sleep 3

echo ""
echo (set_color green)"╔═══════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color green)"║"(set_color normal)"  Interactive Preprocessing Session Started              "(set_color green)"║"(set_color normal)
echo (set_color green)"╚═══════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo "  Frontend: http://localhost:3000"
echo "  Backend:  http://localhost:3001"
echo "  Session:  $session_file"
echo ""
echo "  Browser should open automatically."
echo "  When done, click 'Finish' in the UI."
echo ""
echo "  Press Ctrl+C to pause the session."
echo ""

# Monitor session status
while true
    sleep 2

    if not test -f $session_file
        echo (set_color yellow)"[WARN]"(set_color normal) "Session file disappeared"
        break
    end

    if command -v jq &>/dev/null
        set session_status (jq -r '.status' $session_file 2>/dev/null)

        if test "$session_status" = "completed"
            echo ""
            echo (set_color green)"✓ Session completed!"(set_color normal)
            break
        end
    end

    # Check if processes are still running
    if not ps -p $SERVER_PID &>/dev/null
        echo (set_color yellow)"[WARN]"(set_color normal) "Backend server stopped"
        break
    end
end

# Cleanup
echo ""
echo (set_color cyan)"Shutting down servers..."(set_color normal)
kill $SERVER_PID $VITE_PID 2>/dev/null

echo (set_color green)"✓ Interactive preprocessing session ended"(set_color normal)
echo ""
