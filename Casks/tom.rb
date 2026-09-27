cask "tom" do
  version "1.8"
  sha256 "a3ef4597092e971cb07e92ee5eb14578534f77e0cbcd6d9df828aba8f28c0fec"

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
