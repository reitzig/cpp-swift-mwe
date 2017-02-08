#!/usr/local/bin/ruby

require 'fileutils'

# # # # # # # # # # # # # # # # # # # #
#
#       Parameters
#
# # # # # # # # # # # # # # # # # # # #


# Define relevant system constants

SWIFTC = `which swiftc`.strip
CLANG  = `which clang`.strip
INSTNMTL = `which install_name_tool`.strip

FRAMEWORKS = "/Applications/Xcode8.2/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks" # TODO: determine dynamically
SYSROOT = "/Applications/Xcode8.2/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.12.sdk" # TODO: determine dynamically
CORES = 8

# Define relevant project constants
# TODO: read from Package.swift or CLI parameters

# TODO: configuration: debug vs release --> build folder; opt levels
# =>    Check release.yaml for other differences!

SOURCE_DIR = "Sources"
CPP_DIRS = ["cpplib"]
C_DIRS = ["cwrapper"]
SWIFT_DIRS = ["swift"]

BUILD_DIR = ".build"
DEPENDENCIES = [
    "Dependencies/libcpplib.dylib"
]

# Extract parameters

# TODO: iOS targets!

CONFIG  = :debug
ARCH    = "x86_64"
BIT     = "64"
OSV     = "-mmacosx-version-min=10.10"
TARGET  = "x86_64-apple-macosx10.10"
OPT     = { c: ["-O0"], swift: ["-Onone"] }
# release:
# OPT  = { c: ["-O3"], swift: ["-O", "-whole-module-optimization"] }
# TODO which is the best C option?
#      O2: most opts; O3: more opts, larger code; Oz like O2 but smaller code


# # # # # # # # # # # # # # # # # # # #
#
#       Setup of helper functions
#
# # # # # # # # # # # # # # # # # # # #

# Prints a message to the command line during Makefile construction
def msg(msg, type = :info) # type one of :info, :warn, :error
    prefix = case type
    when :warn
        "Warning: "
    when :error
        "ERROR: "
    else
        ""
    end

    puts "#{prefix}#{msg}"
    Process.exit if error
end

# Appends a new file ending
def new_ending(sourcefile, type)
    #sourcefile.sub(/\.[^.]+$/, ".#{type.to_s}")
    "#{sourcefile}.#{type.to_s}"
end

# Returns the absolute path of the specified file
def abspath(file)
    File.absolute_path(file)
end

# Returns the "library name" of the given module name.
def libname(dir)
    "lib#{dir}.dylib"
end

# Represents a Makefile variable definition
class MakeDef
    @name
    @value

    def initialize(name, value)
        @name = name
        @value = value
    end

    def to_s
        "#{@name} = #{@value}"
    end
end

# Represents a Makefile target/rule
class MakeRule
    @target
    @dependencies = []
    @commands = []

    def initialize(target, dependencies = [], commands = [])
        @target = target
        @dependencies = dependencies
        @commands = commands
    end

    def to_s
        deps = @dependencies.join(" ")
        cmds = @commands.map { |cmd|
            if cmd.is_a?(Array)
                cmd = cmd.join(" ")
            else
                cmd = cmd.to_s
            end

            "\t#{cmd}"
        }.join("\n")

        "#{@target}: #{deps}\n#{cmds}"
    end
end

# Represents a Makefile target/rule that writes stuff into a file
class MakeWriteFile < MakeRule
    def initialize(target, filename, content)
        commands = ["@echo -n \"\" > \"#{filename}\""] +
        content.split("\n").map { |line|
            "@echo \"#{line}\" >> \"#{filename}\""
        }

        super(target, [], commands)
    end
end


# # # # # # # # # # # # # # # # # # # #
#
#       Create Make targets
#
# # # # # # # # # # # # # # # # # # # #

targets = []

# # # # #
# Preamble
# # # # #


# # # # #
# Main targets
# # # # #

targets << MakeRule.new("build",
                        ["build-swift"])

targets << MakeRule.new("clean",
                        [],
                        [["rm", "-rf", "#{BUILD_DIR}"]])

# # # # #
# Prepare build folder
# # # # #

build_dirs = (C_DIRS + SWIFT_DIRS).map { |d| "#{d}.build" }.join(",")

targets << MakeRule.new("mkbuilddir",
                        [],
                        [["mkdir", "-p", "#{BUILD_DIR}/#{CONFIG.to_s}/{#{build_dirs}}"]])

targets << MakeRule.new("copydeps",
                        DEPENDENCIES + ["mkbuilddir"],
                        DEPENDENCIES.map { |d| [
                        ["cp", d, "#{BUILD_DIR}/#{CONFIG.to_s}/"]#,
                        # TODO necessary with libraries that were _really_ built exteranlly?
                        #       [INSTNMTL,
                        #         "-id @executable_path/libcpplib.dylib " +
                        #        "#{BUILD_DIR}/#{CONFIG.to_s}/#{File.basename(d)}"
                        #   ]
                        ]
                        }.flatten(1))

# # # # #
# Build targets for C wrapper libraries
# # # # #

# Order is irrelevant, so just recurse through the folders and
# build compile target for each file individually

targets << MakeRule.new("build-c",
                        C_DIRS.map { |d|
                            [libname(d), "#{d}.modulemap"]
                        }.flatten)

C_DIRS.each { |dir|
    # # # # #
    # Build C wrapper library
    # # # # #

    o_files = []
    Dir["#{SOURCE_DIR}/#{dir}/**/*.{c,cpp}"].each { |src|
        s = File.basename(src) #.sub!(/^#{dir}/, "")
        o = new_ending("#{BUILD_DIR}/#{CONFIG.to_s}/#{dir}.build/#{s}", :o)
        d = new_ending("#{BUILD_DIR}/#{CONFIG.to_s}/#{dir}.build/#{s}", :d)

        o_files << o
        targets << MakeRule.new(o,
                                [src, "copydeps"],
                                [[CLANG, "-F", FRAMEWORKS,
                                         "-fobjc-arc",
                                         "-fmodules",
                                         "-fmodule-name=#{dir}",
                                         "-arch", ARCH,
                                         OSV,
                                         #"-m#{BIT}",
                                         "-isysroot", SYSROOT,
                                         "-fmodules-cache-path=" + abspath("#{BUILD_DIR}/#{CONFIG.to_s}/ModuleCache")] +
                                         CPP_DIRS.map { |cppd|
                                            ["-iquote", abspath("#{SOURCE_DIR}/#{cppd}/include")]
                                         }.flatten + [
                                         "-g"] +
                                         OPT[:c] + [
                                         "-MD",
                                         "-MT", "dependencies",
                                         "-MF", abspath(d),
                                         "-c", abspath(src),
                                         "-o", abspath(o),
                                         "-I", abspath("#{SOURCE_DIR}/#{dir}/include")#,
                                #        "-Wl", "-L" + abspath("#{BUILD_DIR}/#{CONFIG.to_s}"),
                                #        DEPENDENCIES.map { |d|
                                #           ["-Wl", "-l#{File.basename(d)}"]
                                #        }
                                ]])
    }

    # # # # #
    # Link C wrapper library
    # # # # #

    targets << MakeRule.new(libname(dir),
                            o_files + ["copydeps"],
                            [[CLANG,
                            "-F", FRAMEWORKS,
                            #"-arch", ARCH,
                            #OSV,
                            #"-m#{BIT}",
                            "-L" + abspath("#{BUILD_DIR}/#{CONFIG.to_s}")] +
                            CPP_DIRS.map { |d| "-l#{d}" } + #?
                            o_files + # TODO map to abspath(_) ?
                            ["-shared",
                            "-o", abspath("#{BUILD_DIR}/#{CONFIG.to_s}/") + "/#{libname(dir)}"
                            ]])

    # # # # #
    # Write modulemap for C wrapper library
    # # # # #
    # TODO is this the right way to do this?

    headers = Dir["#{SOURCE_DIR}/#{dir}/include/*.h"].map { |f| abspath(f) }
    mmap = abspath("#{BUILD_DIR}/#{CONFIG.to_s}/#{dir}.build/module.modulemap")
    content =
%{module #{dir} {
    #{headers.map { |h| "umbrella header \\\"#{h}\\\""}.join("\n    ")}
    link \\\"#{dir}\\\"
    export *
}}
    # TODO what if there are more headers? Do we include all as "umbrella"?
    targets << MakeWriteFile.new("#{dir}.modulemap", mmap, content)
}

# # # # #
# Build targets for Swift files
# # # # #

targets << MakeRule.new("build-swift",
                        ["build-c"] + SWIFT_DIRS.map { |d| libname(d) } +
                                      SWIFT_DIRS.select { |d|
                                          File.exist?("#{SOURCE_DIR}/#{d}/main.swift")
                                      }.map { |d| "#{d}.exe"}
                        ) # TODO add library target as dependency if there is one

SWIFT_DIRS.each { |dir|
    builddir = "#{BUILD_DIR}/#{CONFIG.to_s}"
    tmpdir = "#{builddir}/#{dir}.build"
    sources = Dir["#{SOURCE_DIR}/#{dir}/**/*.{swift}"]

    # # # # #
    # Construct output file mappings
    # # # # #

    individuals = sources.map { |src|
        basename = new_ending(File.basename(src), "")

        %{      \\\"#{abspath(src)}\\\": {
           \\\"object\\\": \\\"#{abspath(tmpdir)}/#{basename}o\\\",
           \\\"dependencies\\\": \\\"#{abspath(tmpdir)}/#{basename}d\\\",
           \\\"swift-dependencies\\\": \\\"#{abspath(tmpdir)}/#{basename}swiftdeps\\\",
           \\\"diagnostics\\\": \\\"#{abspath(tmpdir)}/#{basename}dia\\\"
         }}
    }

    general = %{    \\\"\\\": {
        \\\"swift-dependencies\\\": \\\"#{abspath(tmpdir)}/main-build-record.swiftdeps\\\"
    }}

    filemappings = "{\n#{individuals.join(",\n")},\n#{general}\n}"

    targets << MakeWriteFile.new("#{dir}.output-file-map",
                                 "#{abspath(tmpdir)}/output-file-map.json",
                                 filemappings)

    # # # # #
    # Build Swift library
    # # # # #

    targets << MakeRule.new(libname(dir),
                            sources + ["copydeps"] +
                                      C_DIRS.map { |d| libname(d) } +
                                      ["#{dir}.output-file-map"],
                            [[SWIFTC,
                                "-emit-object",
                                "-module-name", dir,
                                "-output-file-map", "#{abspath(tmpdir)}/output-file-map.json",
                                "-L", abspath(builddir),
                                "-j#{CORES}",
                                "-D", "SWIFT_PACKAGE"] +
                                OPT[:swift] + [
                                "-g",
                                "-enable-testing",
                                "-F", FRAMEWORKS,
                                "-target", TARGET,
                                # "-target-cpu", ??? # TODO
                                "-sdk", SYSROOT] +
                                C_DIRS.map { |cdir|
                                    ctmpdir = "#{builddir}/#{cdir}.build"
                                    ["-Xcc","-fmodule-map-file=#{abspath(ctmpdir)}/module.modulemap",
                                    "-I", abspath("#{SOURCE_DIR}/#{cdir}/include"),
                                ]}.flatten + [
                                "-module-cache-path", abspath("#{builddir}/ModuleCache")] +
                                sources.map { |s| abspath(s) }
                            ])

    #TODO do we need to change something when building as library?
    # --> -parse-as-library ? -emit-module-path ? -emit-library?


    # # # # #
    # Link Swift library
    # # # # #

    # TODO add target for linking Swift libraries
    #      (create a lib at Starting Point and check what the YAML looks like)

    # # # # #
    # Build Swift executable
    # # # # #

    if File.exist?("#{SOURCE_DIR}/#{dir}/main.swift")
        targets << MakeRule.new("#{dir}.exe",
                                [libname(dir)],
                                [[SWIFTC,
                                    "-target", TARGET,
                                    # "-target-cpu", ??? # TODO
                                    "-sdk", SYSROOT,
                                    "-g",
                                    "-F", FRAMEWORKS,
                                    "-L", abspath(builddir),
                                    "-o", "#{abspath(builddir)}/#{dir}",
                                    "-emit-executable"] +
                                    sources.map { |s|
                                        o = new_ending(File.basename(s), :o)
                                        "#{abspath(tmpdir)}/#{o}"
                                    }
                                    ])
    end
}

# # # # #
# Create fat library
# # # # #

# TODO build fat lib (or executable?) using lipo
#      see e.g. https://gist.github.com/eladnava/0824d08da8f99419ef2c7b7fb6d4cc78

# # # # #
# Create Swift documentation
# # # # #

# TODO


# # # # # # # # # # # # # # # # # # # #
#
#       Write Makefile
#
# # # # # # # # # # # # # # # # # # # #

File.open("Makefile", "w") { |mf|
    mf.write("# Generated on #{Time.now.strftime("%Y-%m-%d %H:%M:%S")} by #{ENV['USERNAME'] || ENV['USER']}\n\n")
    mf.write("SHELL = bash\n\n")
    mf.write(targets.join("\n\n"))
}
