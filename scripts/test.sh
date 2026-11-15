#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/regression-tests .build/test-module-cache
run_test() {
    local name="$1"
    shift
    xcrun swiftc -module-cache-path .build/test-module-cache "$@" "Tests/$name/main.swift" -o ".build/regression-tests/$name"
    ".build/regression-tests/$name"
}
run_test AirPods Notch/Sources/Notch/AirPods.swift
run_test Layout Notch/Sources/Notch/MenuSpacePolicy.swift
run_test NowPlaying Notch/Sources/Notch/SystemNowPlaying.swift
run_test SystemStatus Notch/Sources/Notch/SystemStatus.swift
run_test Playback Notch/Sources/Notch/SystemNowPlaying.swift Notch/Sources/Notch/PlaybackControls.swift Notch/Sources/Notch/ThemedSlider.swift
run_test Sliders Notch/Sources/Notch/ThemedSlider.swift Notch/Sources/Notch/NotchTheme.swift
