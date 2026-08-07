#!/usr/bin/env bash
# Post-remediation checks. Start the bridge first, then:
#   TOKEN=$(cat ~/.config/whisperbridge/token) ./verify_security.sh
set -u
PORT="${PORT:-9877}"
BASE="http://127.0.0.1:$PORT"
TOKEN="${TOKEN:?set TOKEN}"
fails=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (want $2, got $3)"; fails=$((fails+1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@"; }

echo "SEC-01 auth + CORS"
check "status unauth"   401 "$(code "$BASE/status")"
check "status auth"     200 "$(code -H "Authorization: Bearer $TOKEN" "$BASE/status")"
check "no CORS header"  0 "$(curl -s -i --max-time 5 "$BASE/health" | grep -ci 'access-control' || true)"

echo "SEC-03 request validation"
check "text/plain"      415 "$(code -X POST -H 'Content-Type: text/plain' -H "Authorization: Bearer $TOKEN" -d '{"text":"x"}' "$BASE/send")"
check "bad host"        403 "$(code -X POST -H 'Host: evil.example.com' -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d '{"text":"x"}' "$BASE/send")"
check "oversize"        413 "$(code -X POST -H 'Content-Length: 99999999' -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" "$BASE/send")"
check "bad length"      400 "$(code -X POST -H 'Content-Length: notanumber' -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" "$BASE/send")"

echo "SEC-06 header-only auth"
check "querystring auth" 401 "$(code -X POST -H 'Content-Type: application/json' -d '{"text":"x"}' "$BASE/send?token=$TOKEN")"
check "happy path"       200 "$(code -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d '{"text":"verify","mode":"clipboard"}' "$BASE/send")"

echo "SEC-02/07 file permissions"
check "token perms"     600 "$(stat -f '%Lp' "$HOME/.config/whisperbridge/token" 2>/dev/null || echo missing)"
for p in "$HOME/Library/LaunchAgents/com.whisperbridge.launcher.plist" \
         "$HOME/Library/LaunchAgents/com.whisperbridge.menubar.plist"; do
  [ -f "$p" ] && check "$(basename "$p") perms" 600 "$(stat -f '%Lp' "$p")"
done
check "no /tmp log"     0 "$(ls /tmp/whisperbridge.log 2>/dev/null | wc -l | tr -d ' ')"

echo "Android static checks"
A=../android-app/app/src/main
check "no auto-forward"  1 "$(grep -c 'forward("type")' $A/java/com/whisperbridge/ShareReceiverActivity.kt)"
check "pair confirm"     1 "$(grep -c 'setTitle("Pair with \$targetName?")' $A/java/com/whisperbridge/MainActivity.kt)"
check "backup off"       1 "$(grep -c 'allowBackup="false"' $A/AndroidManifest.xml)"
check "no fake domains"  0 "$(grep -c '<domain' $A/res/xml/network_security_config.xml)"

echo
[ "$fails" -eq 0 ] && echo "All checks passed." || echo "$fails check(s) failed."
exit "$fails"
