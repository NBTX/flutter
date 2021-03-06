// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import '../base/common.dart';
import '../base/os.dart';
import '../dart/pub.dart';
import '../project.dart';
import '../runner/flutter_command.dart';
import '../usage.dart';

class PackagesCommand extends FlutterCommand {
  PackagesCommand() {
    addSubcommand(PackagesGetCommand('get', false));
    addSubcommand(PackagesGetCommand('upgrade', true));
    addSubcommand(PackagesTestCommand());
    addSubcommand(PackagesForwardCommand('downgrade', 'Downgrade packages in a Flutter project', requiresPubspec: true));
    addSubcommand(PackagesForwardCommand('publish', 'Publish the current package to pub.dev', requiresPubspec: true));
    addSubcommand(PackagesForwardCommand('deps', 'Print package dependencies', requiresPubspec: true));
    addSubcommand(PackagesForwardCommand('run', 'Run an executable from a package', requiresPubspec: true));
    addSubcommand(PackagesForwardCommand('cache', 'Work with the Pub system cache'));
    addSubcommand(PackagesForwardCommand('version', 'Print Pub version'));
    addSubcommand(PackagesForwardCommand('uploader', 'Manage uploaders for a package on pub.dev'));
    addSubcommand(PackagesForwardCommand('global', 'Work with Pub global packages'));
    addSubcommand(PackagesPassthroughCommand());
  }

  @override
  final String name = 'pub';

  @override
  List<String> get aliases => const <String>['packages'];

  @override
  final String description = 'Commands for managing Flutter packages.';

  @override
  Future<Set<DevelopmentArtifact>> get requiredArtifacts async => const <DevelopmentArtifact>{
    DevelopmentArtifact.universal,
  };

  @override
  Future<FlutterCommandResult> runCommand() async => null;
}

class PackagesGetCommand extends FlutterCommand {
  PackagesGetCommand(this.name, this.upgrade) {
    requiresPubspecYaml();
    argParser.addFlag('offline',
      negatable: false,
      help: 'Use cached packages instead of accessing the network.',
    );
  }

  @override
  final String name;

  final bool upgrade;

  @override
  String get description {
    return '${ upgrade ? "Upgrade" : "Get" } packages in a Flutter project.';
  }

  @override
  String get invocation {
    return '${runner.executableName} pub $name [<target directory>]';
  }

  @override
  Future<Map<String, String>> get usageValues async {
    final Map<String, String> usageValues = <String, String>{};
    final String workingDirectory = argResults.rest.length == 1 ? argResults.rest[0] : null;
    final String target = findProjectRoot(workingDirectory);
    if (target == null) {
      return usageValues;
    }
    final FlutterProject rootProject = FlutterProject.fromPath(target);
    final bool hasPlugins = await rootProject.flutterPluginsFile.exists();
    if (hasPlugins) {
      final int numberOfPlugins = (await rootProject.flutterPluginsFile.readAsLines()).length;
      usageValues[kCommandPackagesNumberPlugins] = '$numberOfPlugins';
    } else {
      usageValues[kCommandPackagesNumberPlugins] = '0';
    }
    usageValues[kCommandPackagesProjectModule] = '${rootProject.isModule}';
    return usageValues;
  }

  Future<void> _runPubGet(String directory) async {
    final Stopwatch pubGetTimer = Stopwatch()..start();
    try {
      await pubGet(context: PubContext.pubGet,
        directory: directory,
        upgrade: upgrade ,
        offline: argResults['offline'],
        checkLastModified: false,
      );
      pubGetTimer.stop();
      flutterUsage.sendEvent('packages-pub-get', 'success');
      flutterUsage.sendTiming('packages-pub-get', 'success', pubGetTimer.elapsed);
    } catch (_) {
      pubGetTimer.stop();
      flutterUsage.sendEvent('packages-pub-get', 'failure');
      flutterUsage.sendTiming('packages-pub-get', 'failure', pubGetTimer.elapsed);
      rethrow;
    }
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (argResults.rest.length > 1)
      throwToolExit('Too many arguments.\n$usage');

    final String workingDirectory = argResults.rest.length == 1 ? argResults.rest[0] : null;
    final String target = findProjectRoot(workingDirectory);
    if (target == null) {
      throwToolExit(
       'Expected to find project root in '
       '${ workingDirectory ?? "current working directory" }.'
      );
    }

    await _runPubGet(target);
    final FlutterProject rootProject = FlutterProject.fromPath(target);
    await rootProject.ensureReadyForPlatformSpecificTooling(checkProjects: true);

    // Get/upgrade packages in example app as well
    if (rootProject.hasExampleApp) {
      final FlutterProject exampleProject = rootProject.example;
      await _runPubGet(exampleProject.directory.path);
      await exampleProject.ensureReadyForPlatformSpecificTooling(checkProjects: true);
    }

    return null;
  }
}

class PackagesTestCommand extends FlutterCommand {
  PackagesTestCommand() {
    requiresPubspecYaml();
  }

  @override
  String get name => 'test';

  @override
  String get description {
    return 'Run the "test" package.\n'
           'This is similar to "flutter test", but instead of hosting the tests in the '
           'flutter environment it hosts the tests in a pure Dart environment. The main '
           'differences are that the "dart:ui" library is not available and that tests '
           'run faster. This is helpful for testing libraries that do not depend on any '
           'packages from the Flutter SDK. It is equivalent to "pub run test".';
  }

  @override
  String get invocation {
    return '${runner.executableName} pub test [<tests...>]';
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    await pub(<String>['run', 'test']..addAll(argResults.rest), context: PubContext.runTest, retry: false);
    return null;
  }
}

class PackagesForwardCommand extends FlutterCommand {
  PackagesForwardCommand(this._commandName, this._description, {bool requiresPubspec = false}) {
    if (requiresPubspec) {
      requiresPubspecYaml();
    }
  }
  final String _commandName;
  final String _description;

  @override
  String get name => _commandName;

  @override
  String get description {
    return '$_description.\n'
           'This runs the "pub" tool in a Flutter context.';
  }

  @override
  String get invocation {
    return '${runner.executableName} pub $_commandName [<arguments...>]';
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    await pub(<String>[_commandName]..addAll(argResults.rest), context: PubContext.pubForward, retry: false);
    return null;
  }

}

class PackagesPassthroughCommand extends FlutterCommand {
  PackagesPassthroughCommand() {
    requiresPubspecYaml();
  }

  @override
  String get name => 'pub';

  @override
  String get description {
    return 'Pass the remaining arguments to Dart\'s "pub" tool.\n'
           'This runs the "pub" tool in a Flutter context.';
  }

  @override
  String get invocation {
    return '${runner.executableName} packages pub [<arguments...>]';
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    await pubInteractively(argResults.rest);
    return null;
  }
}
