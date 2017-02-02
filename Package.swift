import PackageDescription

let package = Package(
    name: "Cpp",
    targets: [Target(name: "cwrapper", dependencies:["cpplib"]),
              Target(name: "swift", dependencies:["cwrapper"]),
              ],
    exclude: ["Dependencies", "build.sh"]
)
