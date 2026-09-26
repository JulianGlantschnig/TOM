cask "tom" do
  version "1.7.1"
  sha256 "f51649c66e89da7b155469ed29f2bed299dd3e84ac1648dbdb33a0a65a37ab69"

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
