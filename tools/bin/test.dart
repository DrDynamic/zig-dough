import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:tools/term.dart' as term;

bool verbose = false;

void logVerbose(Object message) {
  if (verbose) {
    print(term.gray(message));
  }
}

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart test.dart <flags> [arguments]');
  print(argParser.usage);
}

void main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    verbose = results.flag('verbose');

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }

    var interpreter = InterpreterOptions('./zig-out/bin/as', ['--errors=test']);

    if (results.rest.isEmpty) {
      await TestRunner(interpreter).runDir(Directory('./tests'));
    } else {
      await TestRunner(interpreter).runList(results.rest);
    }
  } on FormatException catch (e) {
    print(e);

    print('');
    printUsage(argParser);
  }
}

class InterpreterOptions {
  String interpreter;
  List<String> options;

  InterpreterOptions(this.interpreter, this.options);
}

class TestRunner {
  InterpreterOptions interpreterOption;

  int passed = 0;
  int failed = 0;
  int skiped = 0;
  int expectations = 0;

  TestRunner(this.interpreterOption);

  Future<void> runList(List<String> testFiles) async {
    List<Future> tests = <Future>[];

    for (final path in testFiles) {
      logVerbose("run test: $path");
      tests.add(executeTest(Test(path)));
    }

    await Future.wait(tests);

    if (failed == 0) {
      print(
        "All ${term.green(passed)} tests passed "
        "($expectations expectations).",
      );
    } else {
      print(
        "${term.green(passed)} tests passed. "
        "${term.red(failed)} tests failed.",
      );
    }
  }

  Future<void> runDir(Directory testDir) async {
    logVerbose("run tests in $testDir");

    List<Future> tests = <Future>[];

    await for (final entry in testDir.list(recursive: true)) {
      if (entry is! File) continue;
      if (!entry.path.endsWith('.dough')) continue;

      logVerbose("Dough file found: ${entry.path}");

      tests.add(executeTest(Test(entry.path)));
    }

    await Future.wait(tests);

    if (failed == 0 && skiped == 0) {
      print(
        "All ${term.green(passed)} tests passed "
        "($expectations expectations).",
      );
    } else {
      print(
        "${term.green(passed)} tests passed. "
        "${term.yellow(skiped)} tests skiped. "
        "${term.red(failed)} tests failed.",
      );
    }
  }

  Future<void> executeTest(Test test) async {
    var isTest = await test.parse();
    if (!isTest) return;

    if (test.shouldSkip) {
      skiped += 1;
      return;
    }

    expectations += test.expectations;
    await test.run(interpreterOption);

    if (test.failures.isEmpty) {
      passed += 1;
    } else {
      failed += 1;
      var message = "${term.red("FAIL ${test._path}")} ";

      for (var failure in test.failures) {
        message += "\n     ${term.pink(failure)}";
      }
      print("\n$message");
    }
  }
}

class ExpectedOutput {
  final int line;
  final String output;

  ExpectedOutput(this.line, this.output);
}

class Test {
  final _nonTestPattern = RegExp(r"// nontest");
  final _skipTestPattern = RegExp(r"// skip");
  final _expectedOutputPattern = RegExp(r"// expect: ?(.*)");
  final _expectedCompileErrorPattern = RegExp(r"// expect compile error: (.+)");
  final _errorLinePattern = RegExp(r"// \[line (\d+)\] (Error.*)");
  final _expectedRuntimeErrorPattern = RegExp(r"// expect runtime error: (.+)");
  final _syntaxErrorPattern = RegExp(r"\[.*line (\d+)\] (Error.+)");
  final _stackTracePattern = RegExp(r"\[line (\d+)\]");

  final String _path;
  final _expectedOutput = <ExpectedOutput>[];
  final _expectedCompileErrors = <String>{};
  String? _expectedRuntimeError;
  int _runtimeErrorLine = 0;

  int _expectedExitCode = 0;

  int expectations = 0;

  bool shouldSkip = false;

  /// The list of failure message lines.
  final failures = <String>[];

  Test(this._path);

  Future<bool> parse() async {
    logVerbose("Parsing test: $_path");
    var lines = await File(_path).readAsLines();

    for (var lineNum = 1; lineNum <= lines.length; lineNum++) {
      var line = lines[lineNum - 1];

      var match = _nonTestPattern.firstMatch(line);
      if (match != null) {
        logVerbose("  This is not a test. (Nontest pattern found)");
        return false;
      }

      match = _skipTestPattern.firstMatch(line);
      if (match != null) {
        logVerbose("  This test should be skipped. (Skip pattern found)");
        shouldSkip = true;
        return true;
      }

      match = _expectedOutputPattern.firstMatch(line);
      if (match != null) {
        logVerbose("  output expectation: '${match[1]}' on line $lineNum");
        _expectedOutput.add(ExpectedOutput(lineNum, match[1]!));
        expectations += 1;
        continue;
      }

      match = _expectedCompileErrorPattern.firstMatch(line);
      if (match != null) {
        logVerbose(
          "  compile error expectation: '${match[1]}' on line $lineNum",
        );
        _expectedCompileErrors.add("[$lineNum] ${match[1]}");
        _expectedExitCode = 65; // Compile errors should exit with EX_DATAERR
        expectations += 1;
        continue;
      }

      match = _errorLinePattern.firstMatch(line);
      if (match != null) {
        logVerbose(
          "  compile error expectation: '${match[2]}' on line ${match[1]}",
        );
        _expectedCompileErrors.add("[${match[1]}] ${match[2]}");
        _expectedExitCode = 65; // Compile errors should exit with EX_DATAERR
        expectations += 1;
        continue;
      }

      match = _expectedRuntimeErrorPattern.firstMatch(line);
      if (match != null) {
        logVerbose("  runtime expectation: '${match[1]}' on line $lineNum");

        _runtimeErrorLine = lineNum;
        _expectedRuntimeError = match[1]!;
        _expectedExitCode = 70; // Runtime errors should exit with EX_SOFTWARE
        expectations += 1;
        continue;
      }
    }

    if (_expectedCompileErrors.isNotEmpty && _expectedRuntimeError != null) {
      print("${term.magenta('TEST ERROR')} $_path");
      print("     Cannot expect both compile and runtime errors.");
      print('');
      return false;
    }

    logVerbose("  parsing complete with $expectations expectation(s)");

    return true;
  }

  Future<List<String>> run(InterpreterOptions interpreterOptions) async {
    var result = await Process.run(interpreterOptions.interpreter, [
      ...interpreterOptions.options,
      _path,
    ]);

    // Normalize Windows line endings.
    var outputLines = const LineSplitter().convert(result.stdout as String);
    var errorLines = const LineSplitter().convert(result.stderr as String);

    logVerbose("Running test: $_path");
    logVerbose("  stdio: $outputLines");
    logVerbose("  stderr: $errorLines");

    // Validate that an expected runtime error occurred.
    if (_expectedRuntimeError != null) {
      _validateRuntimeError(errorLines);
    } else {
      _validateCompileErrors(errorLines);
    }

    _validateExitCode(result.exitCode, errorLines);
    _validateOutput(outputLines);
    return failures;
  }

  void _validateOutput(List<String> outputLines) {
    // Remove the trailing last empty line.
    if (outputLines.isNotEmpty && outputLines.last == "") {
      outputLines.removeLast();
    }

    var index = 0;
    for (; index < outputLines.length; index++) {
      var line = outputLines[index];
      if (index >= _expectedOutput.length) {
        fail("Got output '$line' when none was expected.");
        continue;
      }

      var expected = _expectedOutput[index];
      if (expected.output != line) {
        fail(
          "Expected output '${expected.output}' on line ${expected.line} "
          " and got '$line'.",
        );
      }
    }

    while (index < _expectedOutput.length) {
      var expected = _expectedOutput[index];
      fail(
        "Missing expected output '${expected.output}' on line "
        "${expected.line}.",
      );
      index++;
    }
  }

  void _validateCompileErrors(List<String> errorLines) {
    // Validate that every compile error was expected.
    var foundErrors = <String>{};
    var unexpectedCount = 0;
    for (var line in errorLines) {
      var match = _syntaxErrorPattern.firstMatch(line);
      if (match != null) {
        var error = "[${match[1]}] ${match[2]}";
        if (_expectedCompileErrors.contains(error)) {
          foundErrors.add(error);
        } else {
          if (unexpectedCount < 10) {
            fail("Unexpected error:");
            fail(line);
          }
          unexpectedCount++;
        }
      } else if (line != "") {
        if (unexpectedCount < 10) {
          fail("Unexpected output on stderr:");
          fail(line);
        }
        unexpectedCount++;
      }
    }

    if (unexpectedCount > 10) {
      fail("(truncated ${unexpectedCount - 10} more...)");
    }

    // Validate that every expected error occurred.
    for (var error in _expectedCompileErrors.difference(foundErrors)) {
      fail("Missing expected error: $error");
    }
  }

  void _validateRuntimeError(List<String> errorLines) {
    if (errorLines.isEmpty) {
      fail("Expected runtime error '$_expectedRuntimeError' and got none.");
      return;
    }

    if (errorLines[0] != _expectedRuntimeError) {
      fail("Expected runtime error '$_expectedRuntimeError' and got:");
      fail(errorLines[0]);
    }

    // Make sure the stack trace has the right line.
    RegExpMatch? match;
    var stackLines = errorLines.sublist(1);
    for (var line in stackLines) {
      match = _stackTracePattern.firstMatch(line);
      if (match != null) break;
    }

    if (match == null) {
      fail("Expected stack trace and got:", stackLines);
    } else {
      var stackLine = int.parse(match[1]!);
      if (stackLine != _runtimeErrorLine) {
        fail(
          "Expected runtime error on line $_runtimeErrorLine "
          "but was on line $stackLine.",
        );
      }
    }
  }

  void _validateExitCode(int exitCode, List<String> errorLines) {
    if (exitCode == _expectedExitCode) return;

    if (errorLines.length > 10) {
      errorLines = errorLines.sublist(0, 10);
      errorLines.add("(truncated...)");
    }

    fail(
      "Expected return code $_expectedExitCode and got $exitCode. Stderr:",
      errorLines,
    );
  }

  void fail(String message, [List<String>? lines]) {
    failures.add(message);
    if (lines != null) failures.addAll(lines);
  }
}
