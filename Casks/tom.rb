cask "tom" do
  version "1.14"
  sha256 "98cc333ab3bda6da1064b628f34240d3fb03cf2ce53cda07918128e10f9a4dac"

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
