#!/usr/bin/env fish

# run_interactive.fish - Simple launcher for interactive preprocessing
# Usage: ./run_interactive.fish <output_root> [config_file]

set OUTPUT_ROOT $argv[1]
set CONFIG_FILE ""

if test (count $argv) -ge 2
    set CONFIG_FILE $argv[2]
end

if test -z "$OUTPUT_ROOT"
    echo (set_color red)"[ERROR]"(set_color normal) "Usage: ./run_interactive.fish <output_root> [config_file]"
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

    # Add to session JSON (using jq if available)
    if command -v jq &>/dev/null
        jq ".chapters += [{\"name\": \"$chapter_name\", \"pages\": $pages_json}] | .totalPages = $total_pages" $session_file > $session_file.tmp
        mv $session_file.tmp $session_file
    end

    echo (set_color green)"  ✓"(set_color normal) "Chapter: $chapter_name ($page_count pages)"
end

echo (set_color cyan)"Total pages to process: $total_pages"(set_color normal)
echo ""

# Convert session file to absolute path
set session_file_abs (realpath $session_file)

# Kill any existing servers on these ports
echo (set_color cyan)"Checking for existing servers..."(set_color normal)
lsof -ti:3001 | xargs -r kill 2>/dev/null
lsof -ti:3000 | xargs -r kill 2>/dev/null

echo ""
echo (set_color green)"╔═══════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color green)"║"(set_color normal)"  Starting Interactive Preprocessing Servers            "(set_color green)"║"(set_color normal)
echo (set_color green)"╚═══════════════════════════════════════════════════════════╝"(set_color normal)
echo ""

# Start backend in a new terminal or background
echo (set_color cyan)"[1/2] Starting backend server on port 3001..."(set_color normal)
cd interactive-server
pnpm start $session_file_abs 3001 > /tmp/harbinger-backend.log 2>&1 &
set BACKEND_PID $last_pid
cd ..

# Wait for backend to start
sleep 3

# Check if backend is responding
set backend_ok false
for i in (seq 1 5)
    if curl -s http://localhost:3001/api/session > /dev/null 2>&1
        set backend_ok true
        break
    end
    sleep 1
end

if test "$backend_ok" = "false"
    echo (set_color red)"[ERROR]"(set_color normal) "Backend failed to start. Check /tmp/harbinger-backend.log"
    kill $BACKEND_PID 2>/dev/null
    exit 1
end

echo (set_color green)"  ✓ Backend ready"(set_color normal)

# Start frontend
echo (set_color cyan)"[2/2] Starting frontend server on port 3000..."(set_color normal)
cd interactive-preprocessing
pnpm run dev > /tmp/harbinger-frontend.log 2>&1 &
set FRONTEND_PID $last_pid
cd ..

# Wait for frontend to start
sleep 3

echo (set_color green)"  ✓ Frontend ready"(set_color normal)
echo ""
echo (set_color green)"╔═══════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color green)"║"(set_color normal)"  Interactive Preprocessing Session Ready                "(set_color green)"║"(set_color normal)
echo (set_color green)"╚═══════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo "  🌐 Frontend: "(set_color cyan)"http://localhost:3000"(set_color normal)
echo "  🔧 Backend:  "(set_color cyan)"http://localhost:3001"(set_color normal)
echo "  📁 Session:  $session_file"
echo ""
echo "  📊 Total pages: $total_pages"
echo ""
echo (set_color yellow)"  Open http://localhost:3000 in your browser to begin."(set_color normal)
echo ""
echo "  Logs:"
echo "    Backend:  /tmp/harbinger-backend.log"
echo "    Frontend: /tmp/harbinger-frontend.log"
echo ""
echo "  Press Ctrl+C to stop both servers."
echo ""

# Trap Ctrl+C to cleanup
function cleanup
    echo ""
    echo (set_color cyan)"Shutting down servers..."(set_color normal)
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    echo (set_color green)"✓ Servers stopped"(set_color normal)
    exit 0
end

trap cleanup SIGINT SIGTERM

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
    if not ps -p $BACKEND_PID &>/dev/null
        echo (set_color yellow)"[WARN]"(set_color normal) "Backend server stopped unexpectedly"
        echo "Check /tmp/harbinger-backend.log for errors"
        break
    end

    if not ps -p $FRONTEND_PID &>/dev/null
        echo (set_color yellow)"[WARN]"(set_color normal) "Frontend server stopped unexpectedly"
        echo "Check /tmp/harbinger-frontend.log for errors"
        break
    end
end

# Cleanup
cleanup
