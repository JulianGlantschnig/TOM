cask "tom" do
  version "1.11"
  sha256 "3248e479b380e7855e49e29770040a762b3686f4926988db1a104229b029eb72"

  url "https://github.com/JulianGlantschnig/TOM/releases/download/v#{version}/TOM-#{version}.zip"
  name "TOM"
  desc "Menu bar time tracker inspired by Tim"
  homepage "https://github.com/JulianGlantschnig/TOM"

  depends_on macos: :sequoia

  app "TOM.app"

  # Die App ist nicht notarisiert. Ohne diesen Schritt würde macOS das Öffnen blockieren.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/TOM.app"]
  end

  zap trash: [
    "~/Library/Application Support/Timecounter",
    "~/Library/Application Support/TOM",
    "~/Library/Application Support/ZeitOpferung",
    "~/Library/Preferences/com.julianglantschnig.Timecounter.plist",
  ]
end
