//
//  main.swift
//  Sourcery
//
//  Created by Krzysztof Zablocki on 09/12/2016.
//  Copyright © 2016 Pixle. All rights reserved.
//

import Foundation
import Commander
import PathKit
import SourceryRuntime
import SourceryFramework
import SourceryUtils
import SourceryJS
import SourceryLib

extension Path: ArgumentConvertible {
    /// :nodoc:
    public init(parser: ArgumentParser) throws {
        if let path = parser.shift() {
            self.init(path)
        } else {
            throw ArgumentError.missingValue(argument: nil)
        }
    }
}

private enum Validators {
    static func isReadable(path: Path) -> Path {
        if !path.isReadable {
            Log.error("'\(path)' does not exist or is not readable.")
            exit(.invalidePath)
        }

        return path
    }

    static func isFileOrDirectory(path: Path) -> Path {
        _ = isReadable(path: path)

        if !(path.isDirectory || path.isFile) {
            Log.error("'\(path)' isn't a directory or proper file.")
            exit(.invalidePath)
        }

        return path
    }

    static func isWritable(path: Path) -> Path {
        if path.exists && !path.isWritable {
            Log.error("'\(path)' isn't writable.")
            exit(.invalidePath)
        }
        return path
    }
}

extension Configuration {

    func validate() {
        guard !sources.isEmpty else {
            Log.error("No sources provided.")
            exit(.invalidConfig)
        }
        sources.forEach { source in
            if case let .sources(sources) = source {
                _ = sources.allPaths.map(Validators.isReadable(path:))
            }
        }

        guard !templates.isEmpty else {
            Log.error("No templates provided.")
            exit(.invalidConfig)
        }
        _ = templates.allPaths.map(Validators.isReadable(path:))
        _ = output.path.map(Validators.isWritable(path:))
    }

}

enum ExitCode: Int32 {
    case invalidePath = 1
    case invalidConfig
    case other
}

private func exit(_ code: ExitCode) -> Never {
    exit(code.rawValue)
}

#if canImport(ObjectiveC)
func runCLI() {
    command(
        Flag("watch", flag: "w", description: "Watch template for changes and regenerate as needed."),
        Flag("disableCache", description: "Stops using cache."),
        Flag("verbose", flag: "v", description: "Turn on verbose logging, this causes to log everything we can."),
        Flag("logAST", description: "Log AST messages"),
        Flag("logBenchmarks", description: "Log time benchmark info"),
        Flag("parseDocumentation", description: "Include documentation comments for all declarations."),
        Flag("quiet", flag: "q", description: "Turn off any logging, only emmit errors."),
        Flag("prune", flag: "p", description: "Remove empty generated files"),
        Flag("serialParse", description: "Parses the specified sources in serial, rather than in parallel (the default), which can address stability issues in SwiftSyntax."),
        VariadicOption<Path>("sources", description: "Path to a source swift files. File or Directory."),
        VariadicOption<Path>("exclude-sources", description: "Path to a source swift files to exclude. File or Directory."),
        VariadicOption<Path>("templates", description: "Path to templates. File or Directory."),
        VariadicOption<Path>("exclude-templates", description: "Path to templates to exclude. File or Directory."),
        Option<Path>("output", default: "", description: "Path to output. File or Directory. Default is current path."),
        Flag("dry", default: false, description: "Dry run, without file system modifications, will output result and errors in JSON format. Not working with --watch."),
        VariadicOption<Path>("config", default: ["."], description: "Path to config file. File or Directory. Default is current path."),
        VariadicOption<String>("force-parse", description: "File extensions that Sourcery will be forced to parse, even if they were generated by Sourcery."),
        Option<Int>("base-indentation", default: 0, description: "Base indendation to add to sourcery:auto fragments."),
        VariadicOption<String>("args", description:
        	"""
        	Additional arguments to pass to templates. Each argument can have an explicit value or will have \
        	an implicit `true` value. Arguments should be comma-separated without spaces (e.g. --args arg1=value,arg2) \
        	or should be passed one by one (e.g. --args arg1=value --args arg2). Arguments are accessible in templates \
        	via `argument.<name>`. To pass in string you should use escaped quotes (\\").
        	"""),
        Option<Path>("ejsPath", default: "", description: "Path to EJS file for JavaScript templates."),
        Option<Path>("cacheBasePath", default: "", description: "Base path to Sourcery's cache directory"),
        Option<Path>("buildPath", default: "", description: "Sets a custom build path"),
        Flag("hideVersionHeader", description: "Do not include Sourcery version in the generated files headers."),
        Option<String?>("headerPrefix", default: nil, description: "Additional prefix for headers.")
    ) { watcherEnabled, disableCache, verboseLogging, logAST, logBenchmark, parseDocumentation, quiet, prune, serialParse, sources, excludeSources, templates, excludeTemplates, output, isDryRun, configPaths, forceParse, baseIndentation, args, ejsPath, cacheBasePath, buildPath, hideVersionHeader, headerPrefix in
        do {
            let logConfiguration = Log.Configuration(
                isDryRun: isDryRun,
                isQuiet: quiet,
                isVerboseLoggingEnabled: verboseLogging,
                isLogBenchmarkEnabled: logBenchmark,
                shouldLogAST: logAST
            )
            Log.setup(using: logConfiguration)

            // if ejsPath is not provided use default value or executable path
            EJSTemplate.ejsPath = ejsPath.string.isEmpty
                ? (EJSTemplate.ejsPath ?? Path(ProcessInfo.processInfo.arguments[0]).parent() + "ejs.js")
                : ejsPath

            let configurations = configPaths.flatMap { configPath -> [Configuration] in
                let yamlPath: Path = configPath.isDirectory ? configPath + ".sourcery.yml" : configPath

                if !yamlPath.exists {
                    Log.info("No config file provided or it does not exist. Using command line arguments.")
                    let args = args.joined(separator: ",")
                    let arguments = AnnotationsParser.parse(line: args)
                    return [
                        Configuration(
                            sources: Paths(include: sources, exclude: excludeSources) ,
                            templates: Paths(include: templates, exclude: excludeTemplates),
                            output: output.string.isEmpty ? "." : output,
                            cacheBasePath: cacheBasePath.string.isEmpty ? Path.defaultBaseCachePath : cacheBasePath,
                            forceParse: forceParse,
                            parseDocumentation: parseDocumentation,
                            baseIndentation: baseIndentation,
                            args: arguments
                        )
                    ]
                } else {
                    _ = Validators.isFileOrDirectory(path: configPath)
                    _ = Validators.isReadable(path: yamlPath)

                    do {
                        let relativePath: Path = configPath.isDirectory ? configPath : configPath.parent()

                        // Check if the user is passing parameters
                        // that are ignored cause read from the yaml file
                        let hasAnyYamlDuplicatedParameter = (
                            !sources.isEmpty ||
                                !excludeSources.isEmpty ||
                                !templates.isEmpty ||
                                !excludeTemplates.isEmpty ||
                                !forceParse.isEmpty ||
                                output != "" ||
                                !args.isEmpty
                        )

                        if hasAnyYamlDuplicatedParameter {
                            Log.info("Using configuration file at '\(yamlPath)'. WARNING: Ignoring the parameters passed in the command line.")
                        } else {
                            Log.info("Using configuration file at '\(yamlPath)'")
                        }

                        return try Configurations.make(
                            path: yamlPath,
                            relativePath: relativePath,
                            env: ProcessInfo.processInfo.environment
                        )
                    } catch {
                        Log.error("while reading .yml '\(yamlPath)'. '\(error)'")
                        exit(.invalidConfig)
                    }
                }
            }

            let start = currentTimestamp()

            let keepAlive = try configurations.flatMap { configuration -> [FolderWatcher.Local] in
                configuration.validate()
                
                let shouldUseCacheBasePathArg = configuration.cacheBasePath == Path.defaultBaseCachePath && !cacheBasePath.string.isEmpty

                let sourcery = Sourcery(verbose: verboseLogging,
                                        watcherEnabled: watcherEnabled,
                                        cacheDisabled: disableCache,
                                        cacheBasePath: shouldUseCacheBasePathArg ? cacheBasePath : configuration.cacheBasePath,
                                        buildPath: buildPath.string.isEmpty ? nil : buildPath,
                                        prune: prune,
                                        serialParse: serialParse,
                                        hideVersionHeader: hideVersionHeader,
                                        arguments: configuration.args,
                                        headerPrefix: headerPrefix)

                if isDryRun, watcherEnabled {
                    throw "--dry not compatible with --watch"
                }

                return try sourcery.processFiles(
                    configuration.sources,
                    usingTemplates: configuration.templates,
                    output: configuration.output,
                    isDryRun: isDryRun,
                    forceParse: configuration.forceParse,
                    parseDocumentation: configuration.parseDocumentation,
                    baseIndentation: configuration.baseIndentation
                ) ?? []
            }

            if keepAlive.isEmpty {
                Log.info(String(format: "Processing time %.2f seconds", currentTimestamp() - start))
            } else {
                RunLoop.current.run()
                _ = keepAlive
            }
        } catch {
            if isDryRun {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try? encoder.encode(DryOutputFailure(error: "\(error)",
                                                                log: Log.messagesStack))
                data.flatMap { Log.output(String(data: $0, encoding: .utf8) ?? "") }
            } else {
                Log.error("\(error)")
            }

            exit(.other)
        }
        }.run(Sourcery.version)
}

import AppKit

if !inUnitTests {
    runCLI()
} else {
    // ! Need to run something for tests to work
    final class TestApplicationController: NSObject, NSApplicationDelegate {
        let window =   NSWindow()

        func applicationDidFinishLaunching(aNotification: NSNotification) {
            window.setFrame(CGRect(x: 0, y: 0, width: 0, height: 0), display: false)
            window.makeKeyAndOrderFront(self)
        }

        func applicationWillTerminate(aNotification: NSNotification) {
        }

    }

    autoreleasepool { () -> Void in
        let app =   NSApplication.shared
        let controller =   TestApplicationController()

        app.delegate   = controller
        app.run()
    }
}
#else
func runCLI() {
    command(
        Flag("disableCache", description: "Stops using cache."),
        Flag("verbose", flag: "v", description: "Turn on verbose logging, this causes to log everything we can."),
        Flag("logAST", description: "Log AST messages"),
        Flag("logBenchmarks", description: "Log time benchmark info"),
        Flag("parseDocumentation", description: "Include documentation comments for all declarations."),
        Flag("quiet", flag: "q", description: "Turn off any logging, only emmit errors."),
        Flag("prune", flag: "p", description: "Remove empty generated files"),
        Flag("serialParse", description: "Parses the specified sources in serial, rather than in parallel (the default), which can address stability issues in SwiftSyntax."),
        VariadicOption<Path>("sources", description: "Path to a source swift files. File or Directory."),
        VariadicOption<Path>("exclude-sources", description: "Path to a source swift files to exclude. File or Directory."),
        VariadicOption<Path>("templates", description: "Path to templates. File or Directory."),
        VariadicOption<Path>("exclude-templates", description: "Path to templates to exclude. File or Directory."),
        Option<Path>("output", default: "", description: "Path to output. File or Directory. Default is current path."),
        Flag("dry", default: false, description: "Dry run, without file system modifications, will output result and errors in JSON format. Not working with --watch."),
        VariadicOption<Path>("config", default: ["."], description: "Path to config file. File or Directory. Default is current path."),
        VariadicOption<String>("force-parse", description: "File extensions that Sourcery will be forced to parse, even if they were generated by Sourcery."),
        Option<Int>("base-indentation", default: 0, description: "Base indendation to add to sourcery:auto fragments."),
        VariadicOption<String>("args", description:
        	"""
        	Additional arguments to pass to templates. Each argument can have an explicit value or will have \
        	an implicit `true` value. Arguments should be comma-separated without spaces (e.g. --args arg1=value,arg2) \
        	or should be passed one by one (e.g. --args arg1=value --args arg2). Arguments are accessible in templates \
        	via `argument.<name>`. To pass in string you should use escaped quotes (\\").
        	"""),
        Option<Path>("cacheBasePath", default: "", description: "Base path to Sourcery's cache directory"),
        Option<Path>("buildPath", default: "", description: "Sets a custom build path"),
        Flag("hideVersionHeader", description: "Do not include Sourcery version in the generated files headers."),
        Option<String?>("headerPrefix", default: nil, description: "Additional prefix for headers.")
    ) { disableCache, verboseLogging, logAST, logBenchmark, parseDocumentation, quiet, prune, serialParse, sources, excludeSources, templates, excludeTemplates, output, isDryRun, configPaths, forceParse, baseIndentation, args, cacheBasePath, buildPath, hideVersionHeader, headerPrefix in
        do {
            let logConfiguration = Log.Configuration(
                isDryRun: isDryRun,
                isQuiet: quiet,
                isVerboseLoggingEnabled: verboseLogging,
                isLogBenchmarkEnabled: logBenchmark,
                shouldLogAST: logAST
            )
            Log.setup(using: logConfiguration)

            let configurations = configPaths.flatMap { configPath -> [Configuration] in
                let yamlPath: Path = configPath.isDirectory ? configPath + ".sourcery.yml" : configPath

                if !yamlPath.exists {
                    Log.info("No config file provided or it does not exist. Using command line arguments.")
                    let args = args.joined(separator: ",")
                    let arguments = AnnotationsParser.parse(line: args)
                    return [
                        Configuration(
                            sources: Paths(include: sources, exclude: excludeSources) ,
                            templates: Paths(include: templates, exclude: excludeTemplates),
                            output: output.string.isEmpty ? "." : output,
                            cacheBasePath: cacheBasePath.string.isEmpty ? Path.defaultBaseCachePath : cacheBasePath,
                            forceParse: forceParse,
                            parseDocumentation: parseDocumentation,
                            baseIndentation: baseIndentation,
                            args: arguments
                        )
                    ]
                } else {
                    _ = Validators.isFileOrDirectory(path: configPath)
                    _ = Validators.isReadable(path: yamlPath)

                    do {
                        let relativePath: Path = configPath.isDirectory ? configPath : configPath.parent()

                        // Check if the user is passing parameters
                        // that are ignored cause read from the yaml file
                        let hasAnyYamlDuplicatedParameter = (
                            !sources.isEmpty ||
                                !excludeSources.isEmpty ||
                                !templates.isEmpty ||
                                !excludeTemplates.isEmpty ||
                                !forceParse.isEmpty ||
                                output != "" ||
                                !args.isEmpty
                        )

                        if hasAnyYamlDuplicatedParameter {
                            Log.info("Using configuration file at '\(yamlPath)'. WARNING: Ignoring the parameters passed in the command line.")
                        } else {
                            Log.info("Using configuration file at '\(yamlPath)'")
                        }

                        return try Configurations.make(
                            path: yamlPath,
                            relativePath: relativePath,
                            env: ProcessInfo.processInfo.environment
                        )
                    } catch {
                        Log.error("while reading .yml '\(yamlPath)'. '\(error)'")
                        exit(.invalidConfig)
                    }
                }
            }

            let start = currentTimestamp()

            let keepAlive = try configurations.flatMap { configuration -> [FolderWatcher.Local] in
                configuration.validate()
                
                let shouldUseCacheBasePathArg = configuration.cacheBasePath == Path.defaultBaseCachePath && !cacheBasePath.string.isEmpty

                let sourcery = Sourcery(verbose: verboseLogging,
                                        watcherEnabled: false,
                                        cacheDisabled: disableCache,
                                        cacheBasePath: shouldUseCacheBasePathArg ? cacheBasePath : configuration.cacheBasePath,
                                        buildPath: buildPath.string.isEmpty ? nil : buildPath,
                                        prune: prune,
                                        serialParse: serialParse,
                                        hideVersionHeader: hideVersionHeader,
                                        arguments: configuration.args,
                                        headerPrefix: headerPrefix)

                return try sourcery.processFiles(
                    configuration.source,
                    usingTemplates: configuration.templates,
                    output: configuration.output,
                    isDryRun: isDryRun,
                    forceParse: configuration.forceParse,
                    parseDocumentation: configuration.parseDocumentation,
                    baseIndentation: configuration.baseIndentation
                ) ?? []
            }

            if keepAlive.isEmpty {
                Log.info(String(format: "Processing time %.2f seconds", currentTimestamp() - start))
            } else {
                RunLoop.current.run()
                _ = keepAlive
            }
        } catch {
            if isDryRun {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try? encoder.encode(DryOutputFailure(error: "\(error)",
                                                                log: Log.messagesStack))
                data.flatMap { Log.output(String(data: $0, encoding: .utf8) ?? "") }
            } else {
                Log.error("\(error)")
            }

            exit(.other)
        }
        }.run(Sourcery.version)
}

runCLI()
#endif
