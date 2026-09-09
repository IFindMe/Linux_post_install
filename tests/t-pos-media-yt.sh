#!/usr/bin/env bash
set -euo pipefail
# t-pos-media-yt.sh — POS--9 verification for the unified `pos media yt`
# suite and its forwarders.
#
#   Part 1: dispatcher + forwarder resolution (bin/pos-media-yt, pos-media-mp3/
#           mp4/grab forwarders, full chain through bin/pos)
#   Part 2: lib/yt-lib.sh shared helpers (deps, url validation, classify)
#   Part 3: yt-mp3 behaviors (flags, dry-run, YT_OUT_DIR seam, unsafe-URL guard)
#   Part 4: yt-mp4 behaviors (format select flags, mutual exclusions, seam)
#   Part 5: yt-grab classification + delegation (dry-run command strings) + config
#   Part 6: yt-subtitles (defaults, --lang en,ar single-arg, formats),
#           txt conversion (timestamps stripped), unavailable-subs detection
#   Part 7: negative controls mandated by the Architect contract

run_test() {
    local sandbox stubs cfg
    sandbox="$(mksandbox media-yt)"
    stubs="$sandbox/stubs"
    cfg="$sandbox/cfg"
    mkdir -p "$stubs" "$cfg"

    local ytdlp_log="$sandbox/ytdlp.log"
    : > "$ytdlp_log"
    # fake yt-dlp logs its exact argv (one per line) — lets us assert arg
    # counting / no-expansion WITHOUT any network or real binary.
    cat > "$stubs/yt-dlp" <<STUB
#!/usr/bin/env bash
printf 'yt-dlp %s\\n' "\$*" >> "$ytdlp_log"
STUB
    # ffmpeg stub: satisfies the non-dry-run deps guard; not actually used.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/ffmpeg"
    chmod +x "$stubs/yt-dlp" "$stubs/ffmpeg"

    local RB="$ROOT/bin"
    local yt ytd="$RB/pos-media-yt" mp3="$RB/pos-media-yt-mp3" \
          mp4="$RB/pos-media-yt-mp4" grab="$RB/pos-media-yt-grab" \
          subs="$RB/pos-media-yt-subtitles"
    local env_base=(PATH="$stubs:$RB:/usr/bin:/bin" CONFIG_DIR="$cfg" \
                    YT_OUT_DIR="$sandbox/out")

    # ═══ Part 1: dispatcher + forwarders ═══
    # 1.0 bare dispatcher → usage listing subcommands (exit 0)
    test_run_env "${env_base[@]}" -- "$ytd"
    check_rc "dispatcher bare invocation = usage exit 0" 0 "$TR_RC"
    check_contains "dispatcher usage lists mp3" "mp3" "$TR_OUT"
    check_contains "dispatcher usage lists subtitles" "subtitles" "$TR_OUT"

    # 1.1 dispatcher unknown subcommand → hard error, nonzero
    test_run_env "${env_base[@]}" -- "$ytd" bogus
    [ "$TR_RC" -ne 0 ] && printf '  PASS  dispatcher unknown subcommand exits nonzero\n' \
                       || printf '  FAIL  dispatcher unknown subcommand exited 0\n'
    check_contains "dispatcher unknown subcommand message" "unknown yt command" "$TR_OUT"

    # 1.2 forwarder helpers: --help passes through to the real yt usage
    test_run_env "${env_base[@]}" -- "$RB/pos-media-mp3" --help
    check_rc "pos media mp3 --help forwards cleanly" 0 "$TR_RC"
    check_contains "mp3 forwarder shows yt-mp3 usage" "pos media yt mp3 [options]" "$TR_OUT"

    test_run_env "${env_base[@]}" -- "$RB/pos-media-mp4" --help
    check_rc "pos media mp4 --help forwards cleanly" 0 "$TR_RC"
    check_contains "mp4 forwarder shows yt-mp4 usage" "pos media yt mp4 [options]" "$TR_OUT"

    test_run_env "${env_base[@]}" -- "$RB/pos-media-grab" --help
    check_rc "pos media grab --help forwards cleanly" 0 "$TR_RC"
    check_contains "grab forwarder shows yt-grab usage" "pos media yt grab [options]" "$TR_OUT"

    # 1.3 ytsync forwarder --help forwards to pos media ytsync
    test_run_env "${env_base[@]}" -- "$RB/pos-media-yt-ytsync" --help
    check_contains "ytsync forwarder references media ytsync" "media ytsync" "$TR_OUT"

    # 1.4 full dispatch chain: `pos media mp3 <url>` → yt-mp3 (fake yt-dlp called).
    #    `media-yt-mp3` is non-interactive so bin/pos execs it without a tee.
    : > "$ytdlp_log"
    test_run_env "${env_base[@]}" -- "$RB/pos" media mp3 "http://example.com/x"
    check_rc "chain pos media mp3 <url> resolves" 0 "$TR_RC"
    check_contains "chain reaches yt-dlp with -x (audio path)" "-x" "$(cat "$ytdlp_log")"

    # ═══ Part 2: lib/yt-lib.sh helpers ═══
    source "$ROOT/lib/common.sh"
    source "$ROOT/lib/yt-lib.sh"
    # 2.0 yt_validate_url accepts http(s), rejects junk
    yt_validate_url "https://youtube.com/watch?v=x" && printf '  PASS  url valid http/https accepted\n' \
                       || printf '  FAIL  valid https url rejected\n'
    test_run yt_validate_url "ftp://bad"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  invalid url rejected\n' || printf '  FAIL  invalid url accepted\n'
    check_contains "invalid url error message" "not a valid URL" "$TR_OUT"

    # 2.1 classify_url: audio / video / unknown-with-GRAB_DEFAULT
    check_eq "music.youtube → audio" "audio" "$(classify_url "https://music.youtube.com/watch?v=x")"
    check_eq "soundcloud → audio" "audio" "$(classify_url "https://soundcloud.com/a/b")"
    check_eq "youtube.com → video" "video" "$(classify_url "https://youtube.com/watch?v=x")"
    check_eq "vimeo → video" "video" "$(classify_url "https://vimeo.com/123")"
    check_eq "unknown → default video" "video" "$(classify_url "https://example.com/x")"
    check_eq "unknown → GRAB_DEFAULT=audio" "audio" "$(GRAB_DEFAULT=audio classify_url "https://example.com/x")"

    # ═══ Part 3: yt-mp3 ═══
    # 3.0 dry-run requires no deps and prints the yt-dlp command (audio flags)
    test_run_env "${env_base[@]}" -- "$mp3" --dry-run "https://youtube.com/watch?v=dQw4w9WgXcQ"
    check_rc "mp3 dry-run ok" 0 "$TR_RC"
    check_contains "mp3 dry-run has -x --audio-format mp3" "--audio-format mp3" "$TR_OUT"
    check_contains "mp3 dry-run has --embed-metadata" "--embed-metadata" "$TR_OUT"

    # 3.1 --by-artist template
    test_run_env "${env_base[@]}" -- "$mp3" --dry-run --by-artist "https://youtu.be/x"
    check_contains "mp3 --by-artist organizes by artist/uploader" "%(artist,uploader)s/" "$TR_OUT"

    # 3.2 --no-playlist propagated
    test_run_env "${env_base[@]}" -- "$mp3" --dry-run --no-playlist "https://youtube.com/watch?v=x"
    check_contains "mp3 --no-playlist passed through" "--no-playlist" "$TR_OUT"

    # 3.3 --cookies must exist
    test_run_env "${env_base[@]}" -- "$mp3" --dry-run --cookies "$sandbox/nope.txt" "https://youtube.com/watch?v=x"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  mp3 missing cookies file errors\n' \
                       || printf '  FAIL  mp3 accepted missing cookies file\n'

    # 3.4 YT_OUT_DIR seam overrides default output
    test_run_env "${env_base[@]}" -- "$mp3" --dry-run "https://youtube.com/watch?v=x"
    check_contains "mp3 uses YT_OUT_DIR seam" "$sandbox/out/%(title)s.%(ext)s" "$TR_OUT"

    # 3.5 missing dep in non-dry-run → hard error (no yt-dlp on PATH at all)
    test_run_env PATH="/usr/bin:/bin" -- "$mp3" "https://youtube.com/watch?v=x"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  mp3 without yt-dlp in path errors\n' \
                       || printf '  FAIL  mp3 ran without yt-dlp present\n'

    # 3.6 no URL → usage exit 0
    test_run_env "${env_base[@]}" -- "$mp3" --dry-run
    check_rc "mp3 no URL → usage exit 0" 0 "$TR_RC"
    check_contains "mp3 no URL prints usage" "Usage: pos media yt mp3" "$TR_OUT"

    # 3.7 NEGATIVE CONTROL: unsafe URL not expanded — passed as ONE literal arg.
    #    `$(echo pwned)` stays literal inside the URL token; no second pwned word
    #    appears in the argv log (which would mean command substitution ran).
    : > "$ytdlp_log"
    bad='$(echo pwned)'
    test_run_env "${env_base[@]}" -- "$mp3" "http://example.com/$bad"
    check_rc "unsafe URL run (fake yt-dlp) ok" 0 "$TR_RC"
    local logged; logged="$(cat "$ytdlp_log")"
    check_contains "url passed literally (single arg)" "\$(echo pwned)" "$logged"
    check_not_contains "no separate pwned word from substitution" "example.com/  pwned" "$logged"

    # ═══ Part 4: yt-mp4 ═══
    # 4.0 --best
    test_run_env "${env_base[@]}" -- "$mp4" --dry-run --best "https://youtube.com/watch?v=x"
    check_contains "mp4 --best selects bestvideo+bestaudio" "bestvideo*+bestaudio/best" "$TR_OUT"

    # 4.1 --worst
    test_run_env "${env_base[@]}" -- "$mp4" --dry-run --worst "https://youtube.com/watch?v=x"
    check_contains "mp4 --worst selects worst" "-f worst" "$TR_OUT"

    # 4.2 -f id skips prompt
    test_run_env "${env_base[@]}" -- "$mp4" --dry-run -f 22 "https://youtube.com/watch?v=x"
    check_contains "mp4 -f 22 (no prompt)" "-f 22" "$TR_OUT"

    # 4.3 mutual exclusions
    test_run_env "${env_base[@]}" -- "$mp4" --dry-run --best --worst "https://youtube.com/watch?v=x"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  mp4 --best/--worst mutually exclusive\n' \
                       || printf '  FAIL  mp4 allowed --best and --worst together\n'
    test_run_env "${env_base[@]}" -- "$mp4" --dry-run -f 22 --best "https://youtube.com/watch?v=x"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  mp4 --format/--best mutually exclusive\n' \
                       || printf '  FAIL  mp4 allowed --format and --best together\n'

    # 4.4 YT_OUT_DIR seam
    test_run_env "${env_base[@]}" -- "$mp4" --dry-run --best "https://youtube.com/watch?v=x"
    check_contains "mp4 uses YT_OUT_DIR seam" "$sandbox/out/%(title)s.%(ext)s" "$TR_OUT"

    # 4.5 no URL → usage
    test_run_env "${env_base[@]}" -- "$mp4" --dry-run --best
    check_rc "mp4 no URL → usage exit 0" 0 "$TR_RC"
    check_contains "mp4 no URL prints usage" "Usage: pos media yt mp4" "$TR_OUT"

    # ═══ Part 5: yt-grab classification + delegation (dry-run) + config ═══
    # 5.0 music.youtube → audio route (dry-run prints delegate command, no exec)
    test_run_env "${env_base[@]}" -- "$grab" --dry-run "https://music.youtube.com/watch?v=abc"
    check_contains "grab music.youtube routes to yt mp3" "pos media yt mp3" "$TR_OUT"
    check_not_contains "grab music.youtube not routed to mp4" "pos media yt mp4" "$TR_OUT"

    # 5.1 youtube.com → video route (default --best)
    test_run_env "${env_base[@]}" -- "$grab" --dry-run "https://youtube.com/watch?v=xyz"
    check_contains "grab youtube routes to yt mp4" "pos media yt mp4 --best" "$TR_OUT"

    # 5.2 --audio forces audio despite video domain
    test_run_env "${env_base[@]}" -- "$grab" --dry-run --audio "https://youtube.com/watch?v=abc"
    check_contains "grab --audio forces yt mp3" "pos media yt mp3" "$TR_OUT"

    # 5.3 --worst → video --worst
    test_run_env "${env_base[@]}" -- "$grab" --dry-run --worst "https://youtube.com/watch?v=abc"
    check_contains "grab --worst routes to mp4 --worst" "pos media yt mp4 --worst" "$TR_OUT"

    # 5.4 --audio + --video mutually exclusive
    test_run_env "${env_base[@]}" -- "$grab" --dry-run --audio --video "https://youtube.com/watch?v=abc"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  grab --audio/--video mutually exclusive\n' \
                       || printf '  FAIL  grab allowed --audio and --video together\n'

    # 5.5 invalid URL
    test_run_env "${env_base[@]}" -- "$grab" "not-a-url"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  grab rejects invalid url\n' \
                       || printf '  FAIL  grab accepted invalid url\n'
    check_contains "grab error prefixed yt-grab" "yt-grab:" "$TR_OUT"

    # 5.6 unknown domain honors GRAB_DEFAULT via config file (audio)
    printf 'GRAB_DEFAULT=audio\n' > "$cfg/grab.env"
    test_run_env "${env_base[@]}" -- "$grab" --dry-run "https://example.com/x"
    check_contains "grab unknown domain honors GRAB_DEFAULT=audio" "pos media yt mp3" "$TR_OUT"

    # ═══ Part 6: yt-subtitles ═══
    # 6.0 defaults: --write-subs --write-auto-subs --sub-langs best
    test_run_env "${env_base[@]}" -- "$subs" --dry-run "https://youtube.com/watch?v=x"
    check_contains "subs default writes manual subs" "--write-subs" "$TR_OUT"
    check_contains "subs default writes auto subs" "--write-auto-subs" "$TR_OUT"
    check_contains "subs default sub-langs best" "--sub-langs best" "$TR_OUT"

    # 6.1 NEGATIVE CONTROL: --lang en,ar becomes ONE --sub-langs arg
    test_run_env "${env_base[@]}" -- "$subs" --dry-run --lang en,ar "https://youtube.com/watch?v=x"
    check_contains "subs --lang en,ar single arg" "--sub-langs en,ar" "$TR_OUT"
    check_not_contains "subs does not split --lang (no single 'en')" "--sub-langs en " "$TR_OUT"

    # 6.2 --format vtt
    test_run_env "${env_base[@]}" -- "$subs" --dry-run --format vtt "https://youtube.com/watch?v=x"
    check_contains "subs --format vtt" "--sub-format vtt" "$TR_OUT"

    # 6.3 --auto-only drops --write-subs
    test_run_env "${env_base[@]}" -- "$subs" --dry-run --auto-only "https://youtube.com/watch?v=x"
    check_not_contains "subs --auto-only drops manual subs" "--write-subs" "$TR_OUT"
    check_contains "subs --auto-only keeps auto subs" "--write-auto-subs" "$TR_OUT"

    # 6.4 --output dir template
    test_run_env "${env_base[@]}" -- "$subs" --dry-run --output "$sandbox/subs" "https://youtube.com/watch?v=x"
    check_contains "subs --output template" "$sandbox/subs/%(title)s.%(sub_lang)s.%(ext)s" "$TR_OUT"

    # 6.5 invalid --format
    test_run_env "${env_base[@]}" -- "$subs" --dry-run --format bogus "https://youtube.com/watch?v=x"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  subs rejects unknown format\n' \
                       || printf '  FAIL  subs accepted unknown format\n'

    # 6.6 unavailable subs: fake yt-dlp fails with no-subtitle stderr → friendly error
    mkdir -p "$stubs/subsfail"
    cat > "$stubs/subsfail/yt-dlp" <<STUB
#!/usr/bin/env bash
printf 'ERROR: no subtitles found' >&2
exit 1
STUB
    chmod +x "$stubs/subsfail/yt-dlp"
    test_run_env PATH="$stubs/subsfail:/usr/bin:/bin" -- "$subs" "https://youtube.com/watch?v=x"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  subs no-subtitles exits nonzero\n' \
                       || printf '  FAIL  subs no-subtitles exited 0\n'
    check_contains "subs unavailable-subs message" "unavailable subtitles" "$TR_OUT"

    # 6.7 NEGATIVE CONTROL: txt conversion strips SRT timestamps — run the real
#    tool non-dry with a fake yt-dlp that writes an .srt into the cwd; the txt
#    converter must strip timestamps/html and keep the words.
    local txtdir="$sandbox/txtdir"
    mkdir -p "$txtdir" "$stubs/txtsubs"
    cat > "$stubs/txtsubs/yt-dlp" <<STUB
#!/usr/bin/env bash
printf '1\\n00:00:01,000 --> 00:00:02,000\\nHello <i>world</i>\\n\\n2\\n00:00:03,000 --> 00:00:04,000\\nSecond line\\n' > foo.srt
exit 0
STUB
    chmod +x "$stubs/txtsubs/yt-dlp"
    (
        cd "$txtdir"
        env PATH="$stubs/txtsubs:/usr/bin:/bin" "$subs" --format txt "https://youtube.com/watch?v=x"
    ) >"$sandbox/txtrun.log" 2>&1
    local txt; txt="$(cat "$txtdir/foo.txt" 2>/dev/null || true)"
    check_not_contains "txt output strips timestamps" "-->" "$txt"
    check_not_contains "txt output strips html tags" "<i>" "$txt"
    check_contains "txt output keeps words" "Hello world" "$txt"

    # 6.8 subs dry-run skips deps (yt-dlp not in path) — needs no binaries
    test_run_env PATH="/usr/bin:/bin" -- "$subs" --dry-run "https://youtube.com/watch?v=x"
    check_rc "subs dry-run works without yt-dlp (skips deps)" 0 "$TR_RC"
    check_contains "subs dry-run prints yt-dlp cmd" "yt-dlp" "$TR_OUT"

    # 6.9 subs no URL → error (not usage), exit 1
    test_run_env "${env_base[@]}" -- "$subs" --dry-run
    [ "$TR_RC" -ne 0 ] && printf '  PASS  subs no URL exits nonzero\n' \
                       || printf '  FAIL  subs no URL exited 0\n'
    check_contains "subs no URL error message" "missing URL (see --help)" "$TR_OUT"
}
