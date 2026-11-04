#!/usr/bin/env bash
# Compile android/src/main/kotlin/**/MyFileDirectory.kt against the Java
# stand-ins in stubs/ and run the JVM checks. Needs a JDK (javac) and kotlinc.
#   usage: run.sh <kotlin-source-dir> <work-dir> [<log-scan-dir>]
# KOTLINC and JAVAC override the tools; the exit code is the number of failed checks.
# The plugin class itself needs the Flutter embedding, so only MyFileDirectory.kt
# is compiled; the Log-call allowlist check reads every .kt file in <log-scan-dir> (default <kotlin-source-dir>).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$1"
work="$2"
scan="${3:-$src}"
kotlinc="${KOTLINC:-kotlinc}"
javac="${JAVAC:-javac}"
rm -rf "$work" && mkdir -p "$work/stubs" "$work/out"
"$javac" -d "$work/stubs" $(find "$here/stubs" -name '*.java')
"$kotlinc" -nowarn -cp "$work/stubs" "$(find "$src" -name MyFileDirectory.kt)" "$here/test/MyFileDirectoryTest.kt" -d "$work/out"
java -cp "$work/out:$work/stubs:$("$kotlinc" -version >/dev/null 2>&1; dirname "$(command -v "$kotlinc")")/../lib/kotlin-stdlib.jar" MyFileDirectoryTestKt "$scan"
