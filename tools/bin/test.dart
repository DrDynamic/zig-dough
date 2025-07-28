import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:tools/term.dart' as term;


bool verbose = false;

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


void main(List<String> arguments) {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    verbose = results.flag('verbose');

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }

    new TestRunner().runTests(Directory('./tests'));

  } on FormatException catch (e) {
    print(e.message);
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
  void runTests(Directory testDir) {
    testDir.list(recursive: true).listen(
      (entry) {
        if(entry is File) {

          if(entry.path.endsWith('.dough')) {
            if(verbose) {
              print(term.gray("Dough file found: "+entry.path));
            }
          }
        }
      }
    );

    
  }

}

class ExpectedOutput {
  final int line;
  final String output;

  ExpectedOutput(this.line, this.output);
}

class Test{
  final _nonTestPattern = RegExp(r"// nontest");
  final _expectedOutputPattern = RegExp(r"// expect: ?(.*)");
  final _expectedCompileErrorPattern = RegExp(r"// expect compile error: (.+)");
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

  /// The list of failure message lines.
  final _failures = <String>[];

  Test(this._path);

  Future<bool> parse() async {
    var lines = await File(_path).readAsLines();


    for(var lineNum = 1; lineNum <= lines.length; lineNum) {
      var line = lines[lineNum-1];

      var match = _nonTestPattern.firstMatch(line);
      if(match != null) {
        if(verbose) {
          print(term.gray("This is not a test. (Nontest pattern found)"));
        }
        return false;
      }

      match = _expectedOutputPattern.firstMatch(line);
      if(match != null) {
        _expectedOutput.add(ExpectedOutput(lineNum, match[1]!));
        expectations += 1;
        continue;
      }

      match = _expectedCompileErrorPattern.firstMatch(line);
      if(match != null) {
        _expectedCompileErrors.add("[$lineNum] ${match[1]}");
        _expectedExitCode = 65; // Compile errors should exit with EX_DATAERR
        expectations += 1;
        continue;
      }

      match = _expectedRuntimeErrorPattern.firstMatch(line);
      if(match != null) {
        _runtimeErrorLine = lineNum;
        _expectedRuntimeError = match[1]!;
        _expectedExitCode = 70; // Runtime errors should exit with EX_SOFTWARE
        expectations += 1;
        continue;
      }
    }

    if(_expectedCompileErrors.isNotEmpty && _expectedRuntimeError != null) {
      print("${term.magenta('TEST ERROR')} $_path");
      print("     Cannot expect both compile and runtime errors.");
      print('');
      return false;
    }

    return true;
  }

  Future<List<String>> run(InterpreterOptions options) async {

    var result = await Process.run(options.interpreter, options.options);

    // Normalize Windows line endings.
    var outputLines = const LineSplitter().convert(result.stdout as String);
    var errorLines = const LineSplitter().convert(result.stderr as String);

    // Validate that an expected runtime error occurred.
    if (_expectedRuntimeError != null) {
      _validateRuntimeError(errorLines);
    } else {
      _validateCompileErrors(errorLines);
    }

    _validateExitCode(result.exitCode, errorLines);
    _validateOutput(outputLines);
    return _failures;
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
        fail("Expected output '${expected.output}' on line ${expected.line} "
            " and got '$line'.");
      }
    }

    while (index < _expectedOutput.length) {
      var expected = _expectedOutput[index];
      fail("Missing expected output '${expected.output}' on line "
          "${expected.line}.");
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
    if (errorLines.length < 2) {
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
        fail("Expected runtime error on line $_runtimeErrorLine "
            "but was on line $stackLine.");
      }
    }
  }

  void _validateExitCode(int exitCode, List<String> errorLines) {
    if (exitCode == _expectedExitCode) return;

    if (errorLines.length > 10) {
      errorLines = errorLines.sublist(0, 10);
      errorLines.add("(truncated...)");
    }

    fail("Expected return code $_expectedExitCode and got $exitCode. Stderr:",
        errorLines);
  }

  void fail(String message, [List<String>? lines]) {
    _failures.add(message);
    if (lines != null) _failures.addAll(lines);
  }
}